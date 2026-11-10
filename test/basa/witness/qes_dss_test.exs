defmodule Basa.Witness.QESDssTest do
  use BasaWeb.ConnCase, async: false
  use Oban.Testing, repo: Basa.Repo

  import Phoenix.LiveViewTest
  import Basa.WitnessFixtures

  require Ash.Query

  alias Basa.{DssStub, TrustedQESProvider}
  alias Basa.Witness
  alias Basa.Witness.{Party, Verify}
  alias Basa.Witness.QES.{Dss, QualifyWorker}

  defp sign_both(ctx) do
    for user <- [ctx.lessor, ctx.lessee] do
      party =
        Party
        |> Ash.Query.filter(transaction_id == ^ctx.tx.id and user_id == ^user.id)
        |> Ash.read_one!(authorize?: false)

      {:ok, record} = Witness.start_qualified_signature(ctx.tx.id, :trusted, actor: user)
      {:ok, cms} = TrustedQESProvider.sign(user.id, party.legal_name, ctx.tx.basa_hash)
      {:ok, signed} = Witness.complete_qualified_signature(record, cms, actor: user)
      signed
    end
  end

  test "DSS gets the signature and only the BASA-HASH as the document's digest" do
    ctx = sealed_contract()
    {:ok, cms} = TrustedQESProvider.sign("u", "Olena", ctx.tx.basa_hash)

    DssStub.with_dss(
      fn body ->
        assert body["signedDocument"]["bytes"] == Base.encode64(cms)
        assert [%{"digestAlgorithm" => "SHA256", "bytes" => digest}] = body["originalDocuments"]
        assert Base.decode64!(digest) == ctx.tx.basa_hash
        DssStub.recorded()
      end,
      fn ->
        assert {:ok, r} = Dss.validate(cms, ctx.tx.basa_hash)
        refute r.qualified?
        assert r.indication == "INDETERMINATE"
        assert r.level == "N/A"
        assert r.format == "CAdES-BASELINE-B"
        assert r.report["SignedBy"] == "Olena Kovalenko"
      end
    )
  end

  test "valid signatures DSS does not call qualified don't reach level 4" do
    TrustedQESProvider.with_trusted(fn ->
      DssStub.with_dss(DssStub.recorded(), fn ->
        ctx = sealed_contract()
        [signed | _] = sign_both(ctx)
        assert signed.qualification == :not_qualified
        assert signed.qualification_level == "N/A"

        tx = Ash.reload!(ctx.tx, authorize?: false)
        refute tx.qes_signed_at
        result = Verify.transaction(tx)
        assert {{:qualified, :offeror}, :not_qualified} in result.checks
        assert result.ok?

        {:ok, view, _} = live(build_conn() |> sign_in(ctx.lessor), ~p"/transactions/#{tx.id}")
        assert has_element?(view, "#qes-not-qualified")
        assert has_element?(view, "#qes-offeror-not-qualified", "INDETERMINATE, N/A")
        refute has_element?(view, "#qes-done")
      end)
    end)
  end

  test "when DSS is down, the check is retried and level 4 follows" do
    TrustedQESProvider.with_trusted(fn ->
      DssStub.with_dss(:down, fn ->
        ctx = sealed_contract()
        [o, a] = sign_both(ctx)
        assert o.qualification == :unchecked
        assert_enqueued worker: QualifyWorker, args: %{"id" => o.id}

        tx = Ash.reload!(ctx.tx, authorize?: false)
        refute tx.qes_signed_at
        assert {{:qualified, :offeror}, :pending} in Verify.transaction(tx).checks

        {:ok, view, _} = live(build_conn() |> sign_in(ctx.lessor), ~p"/transactions/#{tx.id}")
        assert has_element?(view, "#qes-checking")

        assert {:error, _} = perform_job(QualifyWorker, %{"id" => o.id})

        DssStub.stub(DssStub.qualified())
        assert :ok = perform_job(QualifyWorker, %{"id" => o.id})
        refute Ash.reload!(ctx.tx, authorize?: false).qes_signed_at
        assert :ok = perform_job(QualifyWorker, %{"id" => a.id})

        tx = Ash.reload!(ctx.tx, authorize?: false)
        assert tx.qes_signed_at
        assert Ash.reload!(o, authorize?: false).qualification == :qualified
        assert :ok = perform_job(QualifyWorker, %{"id" => o.id})
      end)
    end)
  end

  test "without a DSS nothing is qualified and nothing is retried" do
    TrustedQESProvider.with_trusted(fn ->
      ctx = sealed_contract()
      [o, _] = sign_both(ctx)
      assert o.qualification == :unchecked
      refute_enqueued worker: QualifyWorker
      refute Ash.reload!(ctx.tx, authorize?: false).qes_signed_at
      assert {:error, :not_configured} = Dss.validate("x", ctx.tx.basa_hash)
    end)
  end

  test "an unexpected DSS answer is not taken as qualified" do
    assert {:error, :bad_response} = Dss.parse(%{"SimpleReport" => %{}})
    assert {:error, :bad_response} = Dss.parse(%{"oops" => 1})

    report =
      update_in(
        DssStub.qualified(),
        ["SimpleReport", "signatureOrTimestampOrEvidenceRecord"],
        fn [t] ->
          [put_in(t, ["Signature", "Indication"], "INDETERMINATE")]
        end
      )

    assert {:ok, %{qualified?: false}} = Dss.parse(report)
    assert {:ok, %{qualified?: true}} = Dss.parse(DssStub.qualified())
  end
end
