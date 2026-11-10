defmodule Basa.Witness.AuthorityTest do
  use Basa.DataCase, async: false
  use Oban.Testing, repo: Basa.Repo

  import Basa.Fixtures
  import Basa.WitnessFixtures
  require Ash.Query

  alias Basa.Witness
  alias Basa.Witness.{AccessLog, AuthorityRequest, Recovery}

  @court %{
    authority: "Pechersk District Court of Kyiv",
    basis: :court_order,
    reference: "757/1234/26"
  }

  defp logs(tx) do
    AccessLog
    |> Ash.Query.filter(transaction_id == ^tx.id and action in [:request, :recovery])
    |> Ash.Query.sort(inserted_at: :asc)
    |> Ash.read!(authorize?: false)
  end

  defp visible_to(user),
    do: Ash.read!(AuthorityRequest, actor: user)

  setup do
    %{filer: user(%{role: :admin}), approver: user(%{role: :admin})}
  end

  test "four eyes, notice to the parties, every step logged", %{filer: filer, approver: approver} do
    ctx = sealed_contract()
    {:ok, r} = Witness.file_authority_request(ctx.tx.id, @court, actor: filer)
    assert r.status == :pending

    assert {:error, _} = Witness.file_authority_request(ctx.tx.id, @court, actor: ctx.lessee)
    assert {:error, _} = Witness.approve_authority_request(r, actor: filer)
    assert {:error, _} = Witness.approve_authority_request(r, actor: ctx.lessor)

    assert visible_to(ctx.lessee) == []

    {:ok, r} = Witness.approve_authority_request(r, actor: approver)
    assert r.status == :approved and r.decided_by_id == approver.id
    assert r.parties_notified_at
    assert_enqueued(worker: Basa.Witness.AuthorityNotifyWorker, args: %{request_id: r.id})
    assert [%{reference: "757/1234/26"}] = visible_to(ctx.lessee)
    assert visible_to(user()) == []

    assert {:error, _} = Witness.approve_authority_request(r, actor: approver)

    assert [filed, approved] = logs(ctx.tx)
    assert filed.reason =~ "filed: Pechersk"
    assert approved.reason =~ "parties told" and approved.reference == "757/1234/26"
  end

  test "notice withheld needs a reason, and can be given later", %{
    filer: filer,
    approver: approver
  } do
    ctx = sealed_contract()

    assert {:error, _} =
             Witness.file_authority_request(ctx.tx.id, Map.put(@court, :notify_parties, false),
               actor: filer
             )

    {:ok, r} =
      Witness.file_authority_request(
        ctx.tx.id,
        Map.merge(@court, %{
          notify_parties: false,
          no_notice_reason: "investigation secrecy, art. 222 CPC"
        }),
        actor: filer
      )

    {:ok, r} = Witness.approve_authority_request(r, actor: approver)
    assert is_nil(r.parties_notified_at)
    refute_enqueued(worker: Basa.Witness.AuthorityNotifyWorker)
    assert visible_to(ctx.lessee) == []
    assert List.last(logs(ctx.tx)).reason =~ "notice withheld: investigation secrecy"

    {:ok, r} = Witness.notify_authority_request(r, actor: filer)
    assert r.parties_notified_at
    assert [_] = visible_to(ctx.lessor)
    assert {:error, _} = Witness.notify_authority_request(r, actor: filer)
  end

  test "a rejected request gives no kit; a draft contract takes no request", %{
    filer: filer,
    approver: approver
  } do
    ctx = sealed_contract()
    {:ok, r} = Witness.file_authority_request(ctx.tx.id, @court, actor: filer)
    assert {:error, _} = Witness.reject_authority_request(r, "", actor: approver)
    {:ok, r} = Witness.reject_authority_request(r, "no court seal on the order", actor: approver)
    assert Recovery.kit(r, approver) == {:error, :not_approved}

    lessor = user()
    lot = published_lot(lessor, basket(lessor, [item(lessor)]), room(lessor))
    starts = hours_from_now(80)

    {:ok, b} =
      Basa.Bookings.book(
        %{lot_id: lot.id, starts_at: starts, ends_at: DateTime.add(starts, 3600)},
        actor: user()
      )

    {:ok, draft} = Witness.open_transaction(b.id, %{}, actor: lessor)
    assert {:error, _} = Witness.file_authority_request(draft.id, @court, actor: filer)
  end

  test "encrypted: the kit opens offline with two key parts, and only then", %{
    filer: filer,
    approver: approver
  } do
    ctx = sealed_contract(storage_mode: :encrypted, photos: ["the speaker, handed over"])
    tx = ctx.tx

    {:ok, act} = Witness.start_act(tx.id, :return, %{terms: %{}}, actor: ctx.lessee)

    {:ok, _} =
      Basa.Witness.Store.add(tx, :photo, "image/jpeg", "returned with a scratch", ctx.lessee,
        act: act
      )

    {:ok, act} = Witness.fix_act(act, actor: ctx.lessee)
    {:ok, sig} = Basa.Witness.Crypto.sign_act(ctx.keys[ctx.lessee.id], act.hash)
    Witness.sign_act!(act, sig, actor: ctx.lessee)

    {:ok, r} = Witness.file_authority_request(tx.id, @court, actor: filer)
    {:ok, r} = Witness.approve_authority_request(r, actor: approver)
    {:ok, kit} = Recovery.kit(r, filer)
    kit = kit |> Jason.encode!() |> Jason.decode!()

    refute Jason.encode!(kit) =~ Base.encode64("the speaker, handed over")

    private = Witness.recovery_private_key()
    {:ok, [p1, _p2, p3]} = Recovery.split_key(private)
    {:ok, rebuilt} = Recovery.combine_key([p1, p3])
    assert {:error, _} = Recovery.combine_key([p1])

    {:ok, %{files: files, report: report}} = Recovery.open_kit(kit, rebuilt)
    contents = Enum.map(files, & &1.content)
    assert "the speaker, handed over" in contents
    assert "returned with a scratch" in contents
    assert report["contract"]["authentic"]
    assert Enum.all?(report["files"], &(&1["result"] == "ok"))
    assert Enum.count(report["files"], & &1["in_signed_manifest"]) == 2

    {other, _} = Basa.Witness.Crypto.recovery_keypair()
    assert Recovery.open_kit(kit, other) == {:error, :wrong_recovery_key}

    [first | rest] = kit["files"]
    changed = %{kit | "files" => [%{first | "stored" => Base.encode64("garbage")} | rest]}
    {:ok, %{report: changed_report}} = Recovery.open_kit(changed, rebuilt)
    assert hd(changed_report["files"])["result"] == "cannot_open"

    {_json, sha} = Recovery.report_json(report)

    {:ok, r} =
      Witness.record_opening(
        r,
        %{
          key_holders: "O. Koval, notary I. Bondar",
          handed_over_to: "court registry, case 757/1234/26",
          report_sha256: Base.decode16!(sha, case: :lower)
        },
        actor: filer
      )

    assert r.status == :opened
    assert Enum.map(logs(tx), & &1.action) == [:request, :request, :recovery, :recovery]
    assert List.last(logs(tx)).reason =~ "opened offline by O. Koval"
  end

  @tag :tmp_dir
  test "mix basa.witness.open_kit writes the files and the report", %{
    filer: f,
    approver: a,
    tmp_dir: dir
  } do
    ctx = sealed_contract(storage_mode: :encrypted, photos: ["kit photo"])
    {:ok, r} = Witness.file_authority_request(ctx.tx.id, @court, actor: f)
    {:ok, r} = Witness.approve_authority_request(r, actor: a)
    {:ok, kit} = Recovery.kit(r, f)
    kit_path = Path.join(dir, "kit.json")
    File.write!(kit_path, Jason.encode!(kit))

    {:ok, [p1, p2, _]} = Recovery.split_key(Witness.recovery_private_key())
    hex = &Base.encode16(&1, case: :lower)
    out = Path.join(dir, "out")

    Mix.shell(Mix.Shell.Process)

    try do
      Mix.Tasks.Basa.Witness.OpenKit.run([
        kit_path,
        "--part",
        hex.(p1),
        "--part",
        hex.(p2),
        "--out",
        out
      ])
    after
      Mix.shell(Mix.Shell.IO)
    end

    assert_received {:mix_shell, :info, [msg]}
    assert msg =~ "Contract authentic: true"
    assert File.read!(Path.join(out, "contract-photo-1.jpg")) == "kit photo"

    [_, sha] = Regex.run(~r/Report SHA-256 \(record it in BASA\): (\w+)/, msg)
    assert hex.(Basa.Witness.Crypto.hash(File.read!(Path.join(out, "report.json")))) == sha
  end

  test "the notice text names the authority and the reference" do
    text =
      Basa.Witness.AuthorityNotifyWorker.text(
        %{authority: "Court X", reference: "12/3"},
        "ABCD1234",
        :en
      )

    assert text =~ "Court X" and text =~ "12/3" and text =~ "ABCD1234"
  end
end
