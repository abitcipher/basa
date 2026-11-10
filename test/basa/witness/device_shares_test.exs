defmodule Basa.Witness.DeviceSharesTest do
  use Basa.DataCase, async: false

  import Basa.WitnessFixtures
  require Ash.Query

  alias Basa.Witness
  alias Basa.Witness.{Crypto, Disclosure, Evidence, KeyShare, Store, Verify}

  defp rows(tx, act_id \\ nil) do
    KeyShare
    |> Ash.Query.filter(transaction_id == ^tx.id)
    |> Ash.read!(authorize?: false)
    |> Enum.filter(&(&1.act_id == act_id))
    |> Map.new(&{&1.owner, &1})
  end

  defp file(tx, act_id \\ nil) do
    Evidence
    |> Ash.Query.filter(transaction_id == ^tx.id and kind == :photo)
    |> Ash.read!(authorize?: false)
    |> Enum.find(&(&1.act_id == act_id))
  end

  defp unwrap(ctx, user, sealed, aad),
    do: Crypto.open_for_device(ctx.box_keys[user.id], sealed, aad)

  describe "encrypted mode" do
    setup do
      sealed_contract(storage_mode: :encrypted, photos: ["the microphone, as handed over"])
    end

    test "after sealing BASA keeps only its share; a device opens with BASA", ctx do
      %{tx: tx} = ctx
      shares = rows(tx)
      assert shares.basa.share
      assert is_nil(shares.offeror.share) and is_nil(shares.acceptor.share)
      assert shares.offeror.sealed_share && shares.acceptor.delivered_at

      photo = file(tx)
      assert Store.key(tx) == {:error, :shares_missing}
      assert {:error, _} = Store.read(photo, tx)

      {:ok, share} = unwrap(ctx, ctx.lessee, shares.acceptor.sealed_share, tx.id)
      assert Store.read(photo, tx, share: share) == {:ok, "the microphone, as handed over"}

      assert {:error, _} = unwrap(ctx, ctx.lessor, shares.acceptor.sealed_share, tx.id)

      assert {:error, _} =
               unwrap(ctx, ctx.lessee, shares.acceptor.sealed_share, Ecto.UUID.generate())

      {:ok, key} = Crypto.recover(Witness.recovery_private_key(), tx.recovery_sealed, tx.id)

      assert {:ok, _} =
               Crypto.decrypt(key, elem(Basa.Storage.get(photo.storage_key), 1), photo.sha256)

      result = Verify.transaction(Witness.get_transaction!(tx.id, authorize?: false))
      assert result.ok?
      assert {:keys, :ok} in result.checks

      assert {:error, _} = Disclosure.build(tx, [0])
      {:ok, package} = Disclosure.build(tx, [0], share: share)
      assert Disclosure.check(package) |> Map.get(:checks) |> Enum.member?({{:file, 0}, :ok})
    end

    test "an act's photos get their own key, delivered when the act is fixed", ctx do
      %{tx: tx} = ctx
      {:ok, act} = Witness.start_act(tx.id, :return, %{terms: %{}}, actor: ctx.lessee)
      {:ok, _} = Store.add(tx, :photo, "image/jpeg", "returned, fine", ctx.lessee, act: act)
      {:ok, act} = Witness.fix_act(act, actor: ctx.lessee)
      {:ok, sig} = Crypto.sign_act(ctx.keys[ctx.lessee.id], act.hash)
      Witness.sign_act!(act, sig, actor: ctx.lessee)

      shares = rows(tx, act.id)
      assert shares.basa.share && is_nil(shares.acceptor.share) && shares.acceptor.sealed_share

      photo = file(tx, act.id)
      assert {:error, _} = Store.read(photo, tx)

      {:ok, share} = unwrap(ctx, ctx.lessor, shares.offeror.sealed_share, act.id)
      assert Store.read(photo, tx, share: share) == {:ok, "returned, fine"}

      {:ok, contract_share} = unwrap(ctx, ctx.lessor, rows(tx).offeror.sealed_share, tx.id)
      assert {:error, _} = Store.read(photo, tx, share: contract_share)

      assert Verify.transaction(Witness.get_transaction!(tx.id, authorize?: false)).ok?
    end

    test "a changed stored file is caught without opening it", %{tx: tx} do
      photo = file(tx)
      :ok = Basa.Storage.put(photo.storage_key, "garbage", "application/octet-stream")
      result = Verify.transaction(tx)
      refute result.ok?
      assert {{:file, 0}, {:error, :changed}} in result.checks
    end
  end

  test "plain mode keeps every share readable, and delivers sealed copies too" do
    ctx = sealed_contract()
    shares = rows(ctx.tx)
    assert shares.offeror.share && shares.offeror.sealed_share
    {:ok, share} = unwrap(ctx, ctx.lessor, shares.offeror.sealed_share, ctx.tx.id)
    assert share == shares.offeror.share
  end
end
