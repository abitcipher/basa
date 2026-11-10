defmodule Basa.LessorStatsTest do
  use BasaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Basa.Fixtures

  setup do
    lessor = user()
    hours = Map.new(1..7, &{to_string(&1), [["10:00", "12:00"]]})

    lot =
      published_lot(lessor, basket(lessor, [item(lessor)]), room(lessor), %{
        title: "Morning studio",
        weekly_hours: hours,
        price_amount: 300
      })

    tomorrow = Date.utc_today() |> Date.add(1)
    starts = DateTime.new!(tomorrow, ~T[10:00:00], "Etc/UTC")

    {:ok, booking} =
      Basa.Bookings.book(
        %{lot_id: lot.id, starts_at: starts, ends_at: DateTime.add(starts, 3600)},
        actor: user()
      )

    %{lessor: lessor, lot: lot, booking: booking, day: tomorrow}
  end

  test "occupancy and earnings per offer and week, only the lessor's own", ctx do
    stats = Basa.Bookings.lessor_stats!(ctx.day, ctx.day, actor: ctx.lessor)

    assert [%{title: "Morning studio", open_hours: 2, booked_hours: 1, occupancy: 50.0} = offer] =
             stats.offers

    assert Decimal.equal?(offer.earnings, 300)
    assert [%{bookings: 1}] = Enum.filter(stats.weeks, &(&1.bookings > 0))
    assert stats.currency == :UAH

    assert %{offers: []} = Basa.Bookings.lessor_stats!(ctx.day, ctx.day, actor: user())
    assert {:error, _} = Basa.Bookings.lessor_stats(ctx.day, ctx.day)
  end

  test "pending and cancelled bookings don't count", ctx do
    {:ok, _} = Basa.Bookings.cancel_booking(ctx.booking, actor: ctx.lessor)

    assert [%{booked_hours: 0, occupancy: +0.0}] =
             Basa.Bookings.lessor_stats!(ctx.day, ctx.day, actor: ctx.lessor).offers
  end

  test "the page: tables with widgets off, the chart widget with widgets on", ctx do
    {:ok, view, _} = ctx.conn |> sign_in(ctx.lessor) |> live(~p"/my/stats")
    assert has_element?(view, "#stats-offers", "Morning studio")
    refute has_element?(view, "[phx-hook=Widget]")

    {:ok, _} =
      Basa.System.update_settings(Basa.System.settings(), %{widgets_enabled: true},
        actor: user(%{role: :admin})
      )

    {:ok, view, _} = ctx.conn |> sign_in(ctx.lessor) |> live(~p"/my/stats")
    assert has_element?(view, "#lessor-stats[data-component=LessorStats]")

    {:ok, _} = Basa.Bookings.cancel_booking(ctx.booking, actor: ctx.lessor)
    assert_push_event(view, "widget:lessor-stats", %{type: "bookings.changed"})
  end
end
