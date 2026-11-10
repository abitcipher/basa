defmodule Basa.LotSearchTest do
  use Basa.DataCase, async: true
  import Basa.Fixtures

  defp offer(attrs, room_attrs \\ %{}) do
    lessor = user()
    published_lot(lessor, basket(lessor, [item(lessor)]), room(lessor, room_attrs), attrs)
  end

  defp titles(args), do: args |> Basa.Search.find_lots() |> Enum.map(& &1.title) |> Enum.sort()

  test "price up to an amount, in one currency" do
    offer(%{title: "Cheap studio", price_amount: 300})
    offer(%{title: "Dear studio", price_amount: 900})
    offer(%{title: "Euro studio", price_amount: 10, currency: :EUR})

    assert titles(%{price_max: 500, currency: :UAH}) == ["Cheap studio"]
    assert titles(%{price_max: 50, currency: :EUR}) == ["Euro studio"]
    assert length(titles(%{price_max: 1})) == 3
  end

  test "only setups that come to you" do
    offer(%{title: "Fixed studio"})
    offer(%{title: "Mobile studio"}, %{mobile: true, service_radius_km: 30})
    assert titles(%{mobile: true}) == ["Mobile studio"]
  end

  test "free on a day: closed days and booked-out days don't match" do
    monday = Date.utc_today() |> Date.add(7) |> Date.beginning_of_week()
    lessor = user()
    room = room(lessor)
    basket = basket(lessor, [item(lessor)])

    lot =
      published_lot(lessor, basket, room, %{
        title: "Mondays 10-11",
        weekly_hours: %{"1" => [["10:00", "11:00"]]}
      })

    assert titles(%{free_on: monday}) == ["Mondays 10-11"]
    assert titles(%{free_on: Date.add(monday, 1)}) == []

    starts = DateTime.new!(monday, ~T[10:00:00], "Etc/UTC")

    {:ok, _} =
      Basa.Bookings.book(
        %{lot_id: lot.id, starts_at: starts, ends_at: DateTime.add(starts, 3600)},
        actor: user()
      )

    assert titles(%{free_on: monday}) == []
  end

  test "sorting by price or newest" do
    offer(%{title: "Studio B", price_amount: 700})
    offer(%{title: "Studio A", price_amount: 200})
    offer(%{title: "Studio C", price_amount: 450})

    order = fn sort -> %{sort: sort} |> Basa.Search.find_lots() |> Enum.map(& &1.title) end
    assert order.(:price_asc) == ["Studio A", "Studio C", "Studio B"]
    assert order.(:price_desc) == ["Studio B", "Studio C", "Studio A"]
    assert order.(:newest) == ["Studio C", "Studio A", "Studio B"]
  end
end
