defmodule Basa.Witness.SalesTest do
  use Basa.DataCase, async: true
  use Oban.Testing, repo: Basa.Repo

  import Basa.Fixtures
  require Ash.Query

  alias Basa.Witness
  alias Basa.Witness.{Contract, Crypto, Party, Store, Verify}

  setup do
    seller = user(%{display_name: "Olena"})
    buyer = user(%{display_name: "Max"})
    mic = item(seller)
    room = room(seller)
    basket = basket(seller, [mic])

    sale =
      published_lot(seller, basket, room, %{
        title: "Neumann for sale",
        deal: :sale,
        price_amount: Decimal.new(30_000),
        price_unit: :hour
      })

    rental = published_lot(seller, basket(seller, [mic]), room, %{title: "Neumann for rent"})

    %{seller: seller, buyer: buyer, mic: mic, sale: sale, rental: rental}
  end

  defp book(lot, user, hours, length \\ 3600) do
    starts = hours_from_now(hours)

    Basa.Bookings.book(
      %{lot_id: lot.id, starts_at: starts, ends_at: DateTime.add(starts, length)},
      actor: user
    )
  end

  defp reload(tx), do: Witness.get_transaction!(tx.id, authorize?: false)

  test "a buyer books one handover for the whole price; nobody else can", ctx do
    assert {:error, _} = book(ctx.sale, ctx.buyer, 30, 7200)
    assert {:ok, booking} = book(ctx.sale, ctx.buyer, 30)
    assert {booking.units, booking.price_amount} == {1, Decimal.new(30_000)}
    assert {:error, error} = book(ctx.sale, user(), 50)
    assert Exception.message(error) =~ "already reserved"
  end

  test "a sale contract: sale template, 14 days for claims, no deposit", ctx do
    {:ok, booking} = book(ctx.sale, ctx.buyer, 30)
    {:ok, tx} = Witness.open_transaction(booking.id, %{}, actor: ctx.buyer)

    assert {tx.contract_type, tx.claims_window_days} == {:sale, 14}
    assert tx.template =~ ~r/^sale-(ua|eu)@1$/

    assert {:error, _} =
             Witness.update_terms(tx, %{deposit_amount: Decimal.new(100)}, actor: ctx.seller)

    {:ok, data} = Contract.data(tx)
    [text] = data.texts
    assert text.title == "Sale contract"
    headings = Enum.map(text.sections, & &1.heading)
    assert "Handover" in headings and "Condition and claims" in headings
    refute "Term" in headings
    assert {:ok, "%PDF" <> _} = Contract.render(tx)
  end

  describe "after sealing" do
    setup ctx do
      {:ok, booking} = book(ctx.sale, ctx.buyer, 30)
      {:ok, tx} = Witness.open_transaction(booking.id, %{}, actor: ctx.buyer)

      keys =
        for user <- [ctx.seller, ctx.buyer], into: %{} do
          {:ok, {private, public}} = Crypto.signing_keypair()

          p =
            Party
            |> Ash.Query.filter(transaction_id == ^tx.id and user_id == ^user.id)
            |> Ash.read_one!(authorize?: false)

          p = Witness.set_legal_name!(p, user.display_name, actor: user)
          Witness.register_device!(p, public, elem(Crypto.recovery_keypair(), 1), actor: user)
          {user.id, private}
        end

      {:ok, _} = Store.add(tx, :photo, "image/jpeg", "the microphone", ctx.seller)
      {:ok, tx} = Witness.prepare_transaction(tx, actor: ctx.seller)

      tx =
        Enum.reduce([ctx.seller, ctx.buyer], tx, fn u, tx ->
          {:ok, sig} = Crypto.sign_seal(keys[u.id], tx.basa_hash)
          Witness.sign_transaction!(tx, sig, actor: u)
        end)

      %{tx: tx, keys: keys}
    end

    defp act(ctx, user, kind, terms, photos \\ []) do
      {:ok, act} = Witness.start_act(ctx.tx.id, kind, %{terms: terms}, actor: user)

      for p <- photos,
          do: {:ok, _} = Store.add(reload(ctx.tx), :photo, "image/jpeg", p, user, act: act)

      {:ok, act} = Witness.fix_act(act, actor: user)
      {:ok, sig} = Crypto.sign_act(ctx.keys[user.id], act.hash)
      Witness.sign_act!(act, sig, actor: user)
    end

    test "the buyer confirms delivery: items sold, every lot with them archived", ctx do
      assert {:error, _} = Witness.start_act(ctx.tx.id, :delivery, %{}, actor: ctx.seller)
      assert {:error, _} = Witness.start_act(ctx.tx.id, :return, %{}, actor: ctx.buyer)

      act(ctx, ctx.buyer, :delivery, %{"note" => "received"}, ["as photographed"])
      tx = reload(ctx.tx)
      assert tx.status == :delivered and tx.claims_until

      assert Ash.reload!(ctx.mic, authorize?: false).sold_at
      assert Ash.reload!(ctx.sale, authorize?: false).state == :archived
      assert Ash.reload!(ctx.rental, authorize?: false).state == :archived

      act(ctx, ctx.buyer, :acceptance, %{})
      assert reload(ctx.tx).status == :closed
      assert Verify.transaction(reload(ctx.tx)).ok?
    end

    test "a hidden defect: the buyer claims, then they settle", ctx do
      act(ctx, ctx.buyer, :delivery, %{}, ["looks fine"])

      assert {:error, _} =
               Witness.start_act(ctx.tx.id, :claim, %{terms: %{"note" => "x"}}, actor: ctx.seller)

      act(ctx, ctx.buyer, :claim, %{"note" => "crackling at high gain", "amount" => "3000"}, [
        "the noise"
      ])

      assert reload(ctx.tx).status == :claimed

      offer = act(ctx, ctx.seller, :settlement, %{"note" => "partial refund of 2000"})
      {:ok, sig} = Crypto.sign_act(ctx.keys[ctx.buyer.id], offer.hash)
      {:ok, _} = Witness.countersign_act(offer, sig, actor: ctx.buyer)

      assert reload(ctx.tx).status == :settled
      assert Verify.transaction(reload(ctx.tx)).ok?
    end
  end
end
