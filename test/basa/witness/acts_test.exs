defmodule Basa.Witness.ActsTest do
  use Basa.DataCase, async: true
  use Oban.Testing, repo: Basa.Repo

  import Basa.Fixtures
  require Ash.Query

  alias Basa.Witness
  alias Basa.Witness.{Act, Crypto, Party, Store, Verify}

  setup do
    lessor = user(%{display_name: "Olena"})
    lessee = user(%{display_name: "Max"})

    lot =
      published_lot(lessor, basket(lessor, [item(lessor)]), room(lessor), %{
        title: "Vocal session"
      })

    starts = hours_from_now(30)

    {:ok, booking} =
      Basa.Bookings.book(
        %{lot_id: lot.id, starts_at: starts, ends_at: DateTime.add(starts, 3600)},
        actor: lessee
      )

    {:ok, tx} = Witness.open_transaction(booking.id, %{}, actor: lessee)
    {:ok, tx} = Witness.update_terms(tx, %{deposit_amount: Decimal.new(1000)}, actor: lessor)

    keys =
      for {user, name} <- [{lessor, "Olena K"}, {lessee, "Max B"}], into: %{} do
        {:ok, {private, public}} = Crypto.signing_keypair()

        p =
          Party
          |> Ash.Query.filter(transaction_id == ^tx.id and user_id == ^user.id)
          |> Ash.read_one!(authorize?: false)

        p = Witness.set_legal_name!(p, name, actor: user)
        Witness.register_device!(p, public, elem(Crypto.recovery_keypair(), 1), actor: user)
        {user.id, private}
      end

    {:ok, _} = Store.add(tx, :photo, "image/jpeg", "handed over: perfect", lessor)
    {:ok, tx} = Witness.prepare_transaction(tx, actor: lessor)

    tx =
      Enum.reduce([lessor, lessee], tx, fn user, tx ->
        {:ok, sig} = Crypto.sign_seal(keys[user.id], tx.basa_hash)
        Witness.sign_transaction!(tx, sig, actor: user)
      end)

    assert tx.status == :sealed and tx.deposit_status == :held
    %{tx: tx, lessor: lessor, lessee: lessee, keys: keys}
  end

  defp reload(tx), do: Witness.get_transaction!(tx.id, authorize?: false)

  defp act(ctx, user, kind, terms, photos \\ []) do
    {:ok, act} = Witness.start_act(ctx.tx.id, kind, %{terms: terms}, actor: user)

    for p <- photos,
        do: {:ok, _} = Store.add(reload(ctx.tx), :photo, "image/jpeg", p, user, act: act)

    {:ok, act} = Witness.fix_act(act, actor: user)
    {:ok, sig} = Crypto.sign_act(ctx.keys[user.id], act.hash)
    Witness.sign_act!(act, sig, actor: user)
  end

  test "return, then the lessor accepts: closed, deposit released, chain verified", ctx do
    returned = act(ctx, ctx.lessee, :return, %{"note" => "all fine"}, ["handed back: perfect"])
    assert returned.status == :effective
    tx = reload(ctx.tx)
    assert tx.status == :returned and tx.claims_until
    assert_enqueued(worker: Basa.Witness.Acts.AutoAcceptWorker, args: %{transaction_id: tx.id})

    accepted = act(ctx, ctx.lessor, :acceptance, %{})
    assert accepted.previous == returned.hash and returned.previous == tx.basa_hash

    tx = reload(tx)
    assert {tx.status, tx.deposit_status} == {:closed, :released}

    result = Verify.transaction(tx)
    assert result.ok?
    assert {{:act, 1}, :ok} in result.checks and {{:act, 2}, :ok} in result.checks
  end

  test "who may do what, and when", ctx do
    assert {:error, _} = Witness.start_act(ctx.tx.id, :return, %{}, actor: ctx.lessor)

    assert {:error, _} =
             Witness.start_act(ctx.tx.id, :claim, %{terms: %{"note" => "x"}}, actor: ctx.lessee)

    assert {:error, _} = Witness.start_act(ctx.tx.id, :return, %{}, actor: user())

    {:ok, draft} = Witness.start_act(ctx.tx.id, :return, %{}, actor: ctx.lessee)
    assert {:error, error} = Witness.fix_act(draft, actor: ctx.lessee)
    assert Exception.message(error) =~ "photos"

    {:ok, _} = Store.add(ctx.tx, :photo, "image/jpeg", "back", ctx.lessee, act: draft)
    {:ok, draft} = Witness.fix_act(draft, actor: ctx.lessee)
    {:ok, {other, _}} = Crypto.signing_keypair()
    {:ok, forged} = Crypto.sign_act(other, draft.hash)
    assert {:error, _} = Witness.sign_act(draft, forged, actor: ctx.lessee)
  end

  test "claim, settlement countersigned: settled, part of the deposit kept", ctx do
    act(ctx, ctx.lessee, :return, %{}, ["back with a scratch"])

    act(ctx, ctx.lessor, :claim, %{"note" => "scratch on the grille", "amount" => "300"}, [
      "the scratch"
    ])

    assert reload(ctx.tx).status == :claimed

    {:ok, too_much} =
      Witness.start_act(
        ctx.tx.id,
        :settlement,
        %{terms: %{"note" => "x", "deposit_kept" => "5000"}},
        actor: ctx.lessee
      )

    assert {:error, _} = Witness.fix_act(too_much, actor: ctx.lessee)

    offer = act(ctx, ctx.lessee, :settlement, %{"note" => "fair", "deposit_kept" => "300"})
    assert offer.status == :awaiting_counter
    assert reload(ctx.tx).status == :claimed

    {:ok, own} = Crypto.sign_act(ctx.keys[ctx.lessee.id], offer.hash)
    assert {:error, _} = Witness.countersign_act(offer, own, actor: ctx.lessee)

    {:ok, sig} = Crypto.sign_act(ctx.keys[ctx.lessor.id], offer.hash)
    assert {:ok, %{status: :effective}} = Witness.countersign_act(offer, sig, actor: ctx.lessor)

    tx = reload(ctx.tx)

    assert {tx.status, tx.deposit_status, tx.deposit_kept} ==
             {:settled, :partly_kept, Decimal.new(300)}

    assert Verify.transaction(tx).ok?
  end

  test "a rejected settlement leaves the claim open; a dispute ends it", ctx do
    act(ctx, ctx.lessee, :return, %{}, ["back"])
    act(ctx, ctx.lessor, :claim, %{"note" => "broken stand"})
    offer = act(ctx, ctx.lessee, :settlement, %{"note" => "nothing", "deposit_kept" => "0"})

    assert {:ok, %{status: :rejected}} = Witness.reject_act(offer, actor: ctx.lessor)
    assert reload(ctx.tx).status == :claimed

    act(ctx, ctx.lessor, :dispute, %{"note" => "we do not agree"})
    tx = reload(ctx.tx)
    assert tx.status == :disputed and tx.deposit_status == :held
    assert Verify.transaction(tx).ok?
  end

  test "no claim in time: BASA accepts the return automatically", ctx do
    act(ctx, ctx.lessee, :return, %{}, ["back"])

    assert {:cancel, _} =
             perform_job(Basa.Witness.Acts.AutoAcceptWorker, %{transaction_id: ctx.tx.id})

    past = DateTime.add(DateTime.utc_now(), -60)
    Ash.update!(reload(ctx.tx), %{claims_until: past}, action: :apply_act, authorize?: false)

    assert {:error, _} =
             Witness.start_act(ctx.tx.id, :claim, %{terms: %{"note" => "x"}}, actor: ctx.lessor)

    assert :ok = perform_job(Basa.Witness.Acts.AutoAcceptWorker, %{transaction_id: ctx.tx.id})
    tx = reload(ctx.tx)
    assert {tx.status, tx.deposit_status} == {:closed, :released}

    assert [_, %{kind: :auto_acceptance, author: :basa, author_signature: nil}] =
             Act
             |> Ash.Query.filter(transaction_id == ^tx.id)
             |> Ash.Query.sort(sequence: :asc)
             |> Ash.read!(authorize?: false)

    assert Verify.transaction(tx).ok?
  end

  test "a changed act is caught", ctx do
    returned = act(ctx, ctx.lessee, :return, %{}, ["back"])

    {:ok, decoded} = Crypto.decode_act(returned.bytes)
    {:ok, other_bytes} = Crypto.encode_act(%{decoded | terms: %{"note" => "edited"}})

    Basa.Repo.query!("UPDATE witness_acts SET bytes = $1 WHERE id = $2", [
      other_bytes,
      Ecto.UUID.dump!(returned.id)
    ])

    result = Verify.transaction(reload(ctx.tx))
    refute result.ok?
    assert {{:act, 1}, {:error, :hash_mismatch}} in result.checks
  end
end
