defmodule Basa.Catalog.LotTest do
  use Basa.DataCase, async: true

  import Basa.Fixtures
  alias Basa.Catalog

  setup do
    lessor = user()
    %{lessor: lessor, room: room(lessor), basket: basket(lessor, [item(lessor)])}
  end

  test "the rule engine publishes a valid lot on submit", ctx do
    lot = lot(ctx.lessor, ctx.basket, ctx.room)
    assert lot.state == :draft

    lot = Catalog.submit_lot!(lot, actor: ctx.lessor)
    assert lot.state == :published
    assert lot.published_at
  end

  test "a lot the rules reject goes back to draft with reasons", ctx do
    lot = lot(ctx.lessor, ctx.basket, ctx.room, %{title: "Hi", price_amount: 0})
    lot = Catalog.submit_lot!(lot, actor: ctx.lessor)

    assert lot.state == :draft
    assert lot.review_note =~ "title is too short"
    assert lot.review_note =~ "price above zero"
  end

  test "very high value offers wait for an admin", ctx do
    expensive = basket(ctx.lessor, [item(ctx.lessor, %{estimated_value: 9_000_000})])
    lot = ctx.lessor |> lot(expensive, ctx.room) |> Catalog.submit_lot!(actor: ctx.lessor)
    assert lot.state == :under_review

    assert {:error, %Ash.Error.Forbidden{}} = Catalog.approve_lot(lot, actor: ctx.lessor)

    admin = user(%{role: :admin})
    assert {:ok, %{state: :published}} = Catalog.approve_lot(lot, actor: admin)
  end

  test "admins can send a lot back to draft", ctx do
    expensive = basket(ctx.lessor, [item(ctx.lessor, %{estimated_value: 9_000_000})])
    lot = ctx.lessor |> lot(expensive, ctx.room) |> Catalog.submit_lot!(actor: ctx.lessor)

    assert {:ok, %{state: :draft, review_note: "Add photos"}} =
             Catalog.reject_lot(lot, "Add photos", actor: user(%{role: :admin}))
  end

  test "a lot can't use someone else's basket or room", ctx do
    stranger = user()

    assert {:error, error} =
             Catalog.create_lot(
               %{
                 title: "Stolen kit",
                 basket_id: ctx.basket.id,
                 room_id: room(stranger).id,
                 price_amount: 1
               },
               actor: stranger
             )

    assert Exception.message(error) =~ "must be one of your own"
  end

  test "drafts are private, published lots are public", ctx do
    lot = lot(ctx.lessor, ctx.basket, ctx.room)
    assert {:error, _} = Catalog.get_lot(lot.id, actor: user())

    Catalog.submit_lot!(lot, actor: ctx.lessor)
    assert {:ok, _} = Catalog.get_lot(lot.id, actor: nil)
  end

  test "search finds lots by city and by distance, including mobile setups", ctx do
    ctx.lessor |> lot(ctx.basket, ctx.room) |> Catalog.submit_lot!(actor: ctx.lessor)

    mobile =
      room(ctx.lessor, %{
        title: "Rig",
        city: "Kyiv",
        lat: 50.45,
        lng: 30.52,
        mobile: true,
        service_radius_km: 40
      })

    ctx.lessor
    |> lot(basket(ctx.lessor, [item(ctx.lessor)]), mobile, %{title: "Mobile rig"})
    |> Catalog.submit_lot!(actor: ctx.lessor)

    assert [%{title: "Vocal studio, hourly"}] = Catalog.search_lots!(%{city: "odesa"}, actor: nil)

    near_kyiv = %{lat: 50.72, lng: 30.52, radius_km: 5}
    assert [%{title: "Mobile rig"}] = Catalog.search_lots!(near_kyiv, actor: nil)

    assert [_, _] =
             Catalog.search_lots!(%{q: "vocal"}, actor: nil) ++
               Catalog.search_lots!(%{q: "rig"}, actor: nil)
  end

  test "items are private to their owner until offered in a published lot", ctx do
    [item] = ctx.basket |> Ash.load!(:items, authorize?: false) |> Map.fetch!(:items)
    assert {:error, _} = Catalog.get_item(item.id, actor: user())

    assert {:error, %Ash.Error.Forbidden{}} =
             Catalog.update_item(item, %{title: "Mine now"}, actor: user())

    ctx.lessor |> lot(ctx.basket, ctx.room) |> Catalog.submit_lot!(actor: ctx.lessor)
    assert {:ok, _} = Catalog.get_item(item.id, actor: user())
  end
end
