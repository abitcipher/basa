defmodule Basa.Witness.WitnessTest do
  use BasaWeb.ConnCase, async: false

  import Basa.Fixtures
  require Ash.Query

  alias Basa.Witness
  alias Basa.Witness.{AccessLog, Crypto, Evidence, KeyShare, Party, Store, Transaction, Verify}

  setup do
    lessor = user(%{display_name: "Lessor Lena"})
    lessee = user(%{display_name: "Lessee Lev"})

    lot =
      published_lot(lessor, basket(lessor, [item(lessor)]), room(lessor), %{
        title: "Vocal session"
      })

    booking = book(lot, lessee, 30)
    {:ok, tx} = Witness.open_transaction(booking.id, %{}, authorize?: false)
    %{lessor: lessor, lessee: lessee, lot: lot, booking: booking, tx: tx}
  end

  defp book(lot, lessee, hours) do
    starts = hours_from_now(hours)

    {:ok, booking} =
      Basa.Bookings.book(
        %{lot_id: lot.id, starts_at: starts, ends_at: DateTime.add(starts, 3600)},
        actor: lessee
      )

    booking
  end

  defp with_witness_config(changes) do
    before = Witness.config()
    Application.put_env(:basa, Witness, Keyword.merge(before, changes))
    on_exit(fn -> Application.put_env(:basa, Witness, before) end)
  end

  defp shares(tx),
    do: KeyShare |> Ash.Query.filter(transaction_id == ^tx.id) |> Ash.read!(authorize?: false)

  defp parties(tx),
    do: Party |> Ash.Query.filter(transaction_id == ^tx.id) |> Ash.read!(authorize?: false)

  defp logs(tx),
    do: AccessLog |> Ash.Query.filter(transaction_id == ^tx.id) |> Ash.read!(authorize?: false)

  defp failed(result), do: for({name, {:error, _}} <- result.checks, do: name)

  describe "opening" do
    test "parties from the booking, three shares, the key sealed for recovery", ctx do
      assert ctx.tx.storage_mode == :plain and ctx.tx.status == :draft

      assert Map.new(parties(ctx.tx), &{&1.role, &1.user_id}) ==
               %{offeror: ctx.lessor.id, acceptor: ctx.lessee.id}

      assert ctx.tx |> shares() |> Enum.map(& &1.owner) |> Enum.sort() == [
               :acceptor,
               :basa,
               :offeror
             ]

      {:ok, key} = Store.key(ctx.tx)

      assert Crypto.recover(Witness.recovery_private_key(), ctx.tx.recovery_sealed, ctx.tx.id) ==
               {:ok, key.key}

      assert {:error, _} = Witness.open_transaction(ctx.booking.id, %{}, authorize?: false)
    end
  end

  describe "evidence" do
    test "plain mode keeps readable files, in order, never twice", %{tx: tx, lessee: lessee} do
      assert {:ok, contract} = Store.add(tx, :contract, "application/pdf", "the contract", lessee)
      assert {:ok, photo} = Store.add(tx, :photo, "image/jpeg", "a photo", lessee)
      assert {contract.position, photo.position} == {0, 1}

      assert {:ok, "a photo", "image/jpeg"} = Basa.Storage.get(photo.storage_key)
      assert Store.read(photo, tx) == {:ok, "a photo"}
      assert {:error, _} = Store.add(tx, :photo, "image/jpeg", "a photo", lessee)
    end

    test "encrypted mode stores only sealed files", %{lot: lot, lessee: lessee} do
      with_witness_config(storage_mode: :encrypted)
      {:ok, tx} = Witness.open_transaction(book(lot, lessee, 60).id, %{}, authorize?: false)
      assert tx.storage_mode == :encrypted

      {:ok, photo} = Store.add(tx, :photo, "image/jpeg", "a photo", lessee)
      {:ok, stored, "application/octet-stream"} = Basa.Storage.get(photo.storage_key)
      refute stored =~ "a photo"
      assert Store.read(photo, tx) == {:ok, "a photo"}
      assert Verify.transaction(tx).ok?
    end

    test "a failing key check stores nothing", %{tx: tx} do
      Basa.Repo.query!(
        "UPDATE witness_key_shares SET share = $1 WHERE owner = 'basa' AND transaction_id = $2",
        [<<3>> <> :crypto.strong_rand_bytes(32), Ecto.UUID.dump!(tx.id)]
      )

      assert {:error, _} = Store.add(tx, :photo, "image/jpeg", "a photo")

      assert Evidence
             |> Ash.Query.filter(transaction_id == ^tx.id)
             |> Ash.count!(authorize?: false) == 0
    end

    test "only drafts take evidence", %{tx: tx} do
      assert Store.add(%{tx | status: :sealed}, :photo, "image/jpeg", "x") ==
               {:error, :not_a_draft}
    end
  end

  describe "verify" do
    setup %{tx: tx, lessee: lessee} do
      {:ok, _} = Store.add(tx, :contract, "application/pdf", "the contract", lessee)
      {:ok, photo} = Store.add(tx, :photo, "image/jpeg", "a photo", lessee)
      %{photo: photo}
    end

    test "a sound draft passes, a changed file is caught, every run is logged", %{
      tx: tx,
      photo: photo
    } do
      assert Verify.transaction(tx).ok?

      :ok = Basa.Storage.put(photo.storage_key, "another photo", "image/jpeg")
      result = Verify.transaction(tx)
      refute result.ok?
      assert failed(result) == [{:file, 1}]

      assert [first, second] = Enum.sort_by(logs(tx), & &1.inserted_at, DateTime)
      assert {first.action, first.result} == {:verify, "ok"}
      assert second.result =~ "failed"
    end

    test "a sealed transaction: manifest, BASA-HASH and both signatures", %{tx: tx} do
      devices =
        for role <- [:offeror, :acceptor],
            into: %{},
            do: {role, elem(Crypto.signing_keypair(), 1)}

      ps = Map.new(parties(tx), &{&1.role, &1})

      evidence =
        Evidence
        |> Ash.Query.filter(transaction_id == ^tx.id)
        |> Ash.Query.sort(position: :asc)
        |> Ash.read!(authorize?: false)

      {:ok, manifest} =
        Crypto.encode_manifest(%{
          transaction_id: tx.id,
          contract_type: "lease",
          template: tx.template,
          jurisdiction: "ua",
          consumer: false,
          parties:
            for(
              role <- [:offeror, :acceptor],
              do: %{
                role: to_string(role),
                user_id: ps[role].user_id,
                public_key: elem(devices[role], 1)
              }
            ),
          files:
            for(
              e <- evidence,
              do: %{
                sha256: e.sha256,
                kind: to_string(e.kind),
                size: e.size,
                media_type: e.media_type
              }
            ),
          created_at: "2026-11-01T12:00:00Z"
        })

      hash = Crypto.basa_hash(manifest)

      for role <- [:offeror, :acceptor] do
        {private, public} = devices[role]
        {:ok, signature} = Crypto.sign_seal(private, hash)

        Basa.Repo.query!(
          "UPDATE witness_parties SET public_key = $1, signature = $2 WHERE id = $3",
          [public, signature, Ecto.UUID.dump!(ps[role].id)]
        )
      end

      Basa.Repo.query!(
        "UPDATE witness_transactions SET manifest = $1, basa_hash = $2 WHERE id = $3",
        [
          manifest,
          hash,
          Ecto.UUID.dump!(tx.id)
        ]
      )

      sealed = Witness.get_transaction!(tx.id, authorize?: false)
      result = Verify.transaction(sealed)
      assert result.ok?
      assert {{:signature, :acceptor}, :ok} in result.checks

      {:ok, {other, _}} = Crypto.signing_keypair()
      {:ok, forged} = Crypto.sign_seal(other, hash)

      Basa.Repo.query!("UPDATE witness_parties SET signature = $1 WHERE id = $2", [
        forged,
        Ecto.UUID.dump!(ps[:acceptor].id)
      ])

      assert failed(Verify.transaction(sealed)) == [{:signature, :acceptor}]
    end

    test "the mix task checks all and fails loudly" do
      assert ExUnit.CaptureIO.capture_io(fn -> Mix.Tasks.Basa.Witness.Verify.run(["--all"]) end) =~
               "1 checked, 0 failed"
    end
  end

  describe "who sees what" do
    test "parties read their transaction; others and even admins never read key shares", ctx do
      stranger = user()
      admin = user(%{role: :admin})

      assert {:ok, _} = Witness.get_transaction(ctx.tx.id, actor: ctx.lessee)
      assert {:ok, _} = Witness.get_transaction(ctx.tx.id, actor: ctx.lessor)
      assert {:error, _} = Witness.get_transaction(ctx.tx.id, actor: stranger)

      assert length(shares(ctx.tx)) == 3
      assert Ash.read(KeyShare, actor: admin) == {:ok, []}
      assert Ash.read(KeyShare, actor: ctx.lessor) == {:ok, []}

      assert {:error, %Ash.Error.Forbidden{}} =
               Witness.open_transaction(book(ctx.lot, ctx.lessee, 90).id, %{}, actor: stranger)
    end

    test "evidence is never served through /media", %{conn: conn, tx: tx} do
      {:ok, photo} = Store.add(tx, :photo, "image/jpeg", "a photo")
      assert conn |> get("/media/" <> photo.storage_key) |> response(404)

      :ok = Basa.Storage.put("items/x/photo.jpg", "public photo", "image/jpeg")
      assert conn |> get("/media/items/x/photo.jpg") |> response(200) == "public photo"
    end
  end

  test "production refuses an unsafe witness setup" do
    {_, public} = Crypto.recovery_keypair()
    good = [storage_mode: :encrypted, recovery_public_key: public]

    assert Witness.check_config!(:prod, good) == :ok
    assert Witness.check_config!(:dev, storage_mode: :plain) == :ok

    assert_raise RuntimeError, ~r/plain storage/, fn ->
      Witness.check_config!(:prod, Keyword.put(good, :storage_mode, :plain))
    end

    assert_raise RuntimeError, ~r/private key/, fn ->
      Witness.check_config!(:prod, Keyword.put(good, :recovery_private_key, "secret"))
    end

    assert_raise RuntimeError, ~r/WITNESS_RECOVERY_PUBLIC_KEY/, fn ->
      Witness.check_config!(:prod, Keyword.delete(good, :recovery_public_key))
    end
  end

  test "the open transaction id is in every recovery seal", %{tx: tx} do
    assert {:error, _} =
             Crypto.recover(
               Witness.recovery_private_key(),
               tx.recovery_sealed,
               Ecto.UUID.generate()
             )

    assert Transaction |> Ash.count!(authorize?: false) == 1
  end
end
