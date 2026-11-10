defmodule BasaWeb.ScheduleLiveTest do
  use BasaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Basa.Fixtures

  setup do
    lessor = user()
    room = room(lessor, %{title: "Studio A"})
    mic = item(lessor, %{title: "Neumann U87"})

    lot =
      published_lot(lessor, basket(lessor, [mic]), room, %{
        title: "Vocal session",
        booking_mode: :request
      })

    lessee = user(%{display_name: "Olena"})
    starts = hours_from_now(26)

    {:ok, booking} =
      Basa.Bookings.book(
        %{lot_id: lot.id, starts_at: starts, ends_at: DateTime.add(starts, 7200)},
        actor: lessee
      )

    %{lessor: lessor, lot: lot, booking: booking, mic: mic, room: room}
  end

  describe "the actions" do
    test "schedule: the actor's own bookings as lessor", %{lessor: lessor, booking: booking} do
      today = Date.utc_today()
      assert [row] = Basa.Bookings.lessor_schedule!(today, Date.add(today, 7), actor: lessor)
      assert row.id == booking.id and row.lot_title == "Vocal session" and row.lessee == "Olena"
      assert row.status == :pending

      assert [] = Basa.Bookings.lessor_schedule!(today, Date.add(today, 7), actor: user())
      assert {:error, _} = Basa.Bookings.lessor_schedule(today, Date.add(today, 7))

      assert {:error, _} =
               Basa.Bookings.lessor_schedule(today, Date.add(today, 120), actor: lessor)
    end

    test "timeline: every room, item and attendant with its booked time", ctx do
      today = Date.utc_today()
      rows = Basa.Bookings.lessor_timeline!(today, Date.add(today, 7), actor: ctx.lessor)

      mic = Enum.find(rows, &(&1.id == ctx.mic.id))
      room = Enum.find(rows, &(&1.id == ctx.room.id))
      assert mic.type == :item and room.type == :room
      assert [%{booking_id: id, lot_title: "Vocal session"}] = mic.bookings
      assert id == ctx.booking.id
      assert length(room.bookings) == 1
    end
  end

  describe "the requests board" do
    test "a drop on a column means one action, or none" do
      move = &BasaWeb.My.ScheduleLive.move/2
      assert move.(:pending, "confirmed") == "confirm"
      assert move.(:pending, "closed") == "decline"
      assert move.(:confirmed, "completed") == "complete"
      assert move.(:confirmed, "closed") == "cancel"
      assert move.(:pending, "completed") == nil
      assert move.(:completed, "pending") == nil
    end

    test "widgets off: requests by status", %{conn: conn, lessor: lessor} do
      {:ok, view, _} = conn |> sign_in(lessor) |> live(~p"/my/schedule?view=requests")
      assert has_element?(view, "#requests-pending", "Vocal session")
      refute has_element?(view, "#requests-confirmed", "Vocal session")
    end
  end

  describe "widgets off" do
    test "bookings by day; one opens with its actions", %{
      conn: conn,
      lessor: lessor,
      booking: booking
    } do
      {:ok, view, html} = conn |> sign_in(lessor) |> live(~p"/my/schedule")
      assert html =~ "Vocal session" and html =~ "Olena"
      refute has_element?(view, "[phx-hook=Widget]")

      view |> element("button[phx-value-id='#{booking.id}']") |> render_click()
      assert has_element?(view, "#booking-panel")

      view |> element("#booking-panel button", "Confirm") |> render_click()
      assert Ash.reload!(booking, authorize?: false).status == :confirmed
      assert has_element?(view, "#booking-panel button", "Mark as done")
    end

    test "by room and gear", %{conn: conn, lessor: lessor} do
      {:ok, _view, html} = conn |> sign_in(lessor) |> live(~p"/my/schedule?view=resources")
      assert html =~ "Neumann U87" and html =~ "Studio A"
    end

    test "a new booking shows up live", %{conn: conn, lessor: lessor, lot: lot} do
      {:ok, view, _} = conn |> sign_in(lessor) |> live(~p"/my/schedule")
      starts = hours_from_now(50)

      {:ok, _} =
        Basa.Bookings.book(
          %{lot_id: lot.id, starts_at: starts, ends_at: DateTime.add(starts, 3600)},
          actor: user(%{display_name: "Taras"})
        )

      assert render(view) =~ "Taras"
    end

    test "another lessor's booking doesn't open", %{conn: conn, booking: booking} do
      {:ok, view, _} = conn |> sign_in(user()) |> live(~p"/my/schedule")
      render_hook(view, "open_booking", %{"id" => booking.id})
      refute has_element?(view, "#booking-panel")
    end
  end

  describe "widgets on" do
    setup do
      {:ok, _} =
        Basa.System.update_settings(Basa.System.settings(), %{widgets_enabled: true},
          actor: user(%{role: :admin})
        )

      :ok
    end

    test "SVAR calendar and timeline; their packets open bookings", ctx do
      {:ok, view, _} = ctx.conn |> sign_in(ctx.lessor) |> live(~p"/my/schedule")
      assert has_element?(view, "#schedule-calendar[data-component=LessorCalendar]")

      render_hook(view, "widget:event", %{
        "widget" => "schedule-calendar",
        "component" => "LessorCalendar",
        "type" => "booking.opened",
        "data" => %{"bookingId" => ctx.booking.id}
      })

      assert has_element?(view, "#booking-panel", "Vocal session")

      {:ok, view, html} = ctx.conn |> sign_in(ctx.lessor) |> live(~p"/my/schedule?view=resources")
      assert has_element?(view, "#schedule-resources[data-component=ResourceTimeline]")

      [props] =
        html
        |> Floki.parse_document!()
        |> Floki.find("#schedule-resources")
        |> Floki.attribute("data-props")

      labels = Jason.decode!(props)["labels"]
      assert %{"day" => "Day", "week" => "Week", "month" => "Month", "today" => "Today"} = labels

      assert %{
               "pending" => _,
               "confirmed" => _,
               "completed" => _,
               "rooms" => _,
               "items" => _,
               "people" => _
             } = labels

      render_hook(view, "widget:event", %{
        "widget" => "schedule-resources",
        "component" => "ResourceTimeline",
        "type" => "booking.opened",
        "data" => %{"bookingId" => ctx.booking.id}
      })

      assert has_element?(view, "#booking-panel", "Vocal session")
    end

    test "moving a card runs the Ash action; impossible moves are refused", ctx do
      {:ok, view, _} = ctx.conn |> sign_in(ctx.lessor) |> live(~p"/my/schedule?view=requests")
      assert has_element?(view, "#schedule-requests[data-component=BookingBoard]")

      moved = fn to ->
        render_hook(view, "widget:event", %{
          "widget" => "schedule-requests",
          "component" => "BookingBoard",
          "type" => "booking.moved",
          "data" => %{"bookingId" => ctx.booking.id, "to" => to}
        })
      end

      assert moved.("completed") =~ "This move isn&#39;t possible."
      assert Ash.reload!(ctx.booking, authorize?: false).status == :pending
      assert_push_event(view, "widget:schedule-requests", %{type: "bookings.changed"})

      moved.("confirmed")
      assert Ash.reload!(ctx.booking, authorize?: false).status == :confirmed
    end

    test "another lessor can't move someone else's booking", ctx do
      {:ok, view, _} = ctx.conn |> sign_in(user()) |> live(~p"/my/schedule?view=requests")

      render_hook(view, "widget:event", %{
        "widget" => "schedule-requests",
        "component" => "BookingBoard",
        "type" => "booking.moved",
        "data" => %{"bookingId" => ctx.booking.id, "to" => "confirmed"}
      })

      assert Ash.reload!(ctx.booking, authorize?: false).status == :pending
    end

    test "changes reach the widgets as packets", ctx do
      {:ok, view, _} = ctx.conn |> sign_in(ctx.lessor) |> live(~p"/my/schedule")
      {:ok, _} = Basa.Bookings.confirm_booking(ctx.booking, actor: ctx.lessor)
      assert_push_event(view, "widget:schedule-calendar", %{type: "bookings.changed"})
    end
  end
end
