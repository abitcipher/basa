defmodule BasaWeb.LesseeFlowTest do
  use BasaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Basa.Fixtures

  setup do
    lessor = user()
    room = room(lessor, %{title: "Studio A", city: "Odesa"})

    lot =
      published_lot(lessor, basket(lessor, [item(lessor, %{title: "Neumann U87"})]), room, %{
        timezone: "Europe/Kyiv"
      })

    %{lessor: lessor, lot: lot}
  end

  test "anyone can search and open a published offer", %{conn: conn, lot: lot} do
    {:ok, view, html} = live(conn, ~p"/?city=Odesa")
    assert html =~ lot.title

    {:ok, _view, html} =
      view |> element("a[href='/lots/#{lot.id}']") |> render_click() |> follow_redirect(conn)

    assert html =~ "Neumann U87"
    assert html =~ "Pick a time"
  end

  describe "widgets off (server-rendered pages, the default in tests)" do
    test "no widget code on the page", %{conn: conn, lot: lot} do
      {:ok, view, _html} = live(conn, ~p"/lots/#{lot.id}")
      refute has_element?(view, "[phx-hook=Widget]")
      assert has_element?(view, "button[phx-click=pick_date]")
      assert has_element?(view, "#lot-map[data-readonly]")
    end

    test "a signed-in lessee books a slot and sees it under Bookings", %{conn: conn, lot: lot} do
      conn = sign_in(conn, user())
      {:ok, view, _html} = live(conn, ~p"/lots/#{lot.id}")

      view
      |> element(
        "button[phx-click=pick_date]",
        Calendar.strftime(Date.add(today(lot), 1), "%d.%m")
      )
      |> render_click()

      view |> element("#slots button", "12:00") |> render_click()
      assert render(view) =~ "Until"

      assert {:error, {:live_redirect, %{to: "/bookings"}}} =
               view |> form("form[phx-submit=book]", %{note: "Hi!"}) |> render_submit()

      {:ok, _view, html} = live(conn, ~p"/bookings")
      assert html =~ lot.title
      assert html =~ "Confirmed"
    end

    test "taken slots update live for other viewers", %{conn: conn, lot: lot} do
      {:ok, view, _html} = live(conn, ~p"/lots/#{lot.id}")
      tomorrow = Date.add(today(lot), 1)

      view
      |> element("button[phx-click=pick_date]", Calendar.strftime(tomorrow, "%d.%m"))
      |> render_click()

      refute has_element?(view, "#slots button[disabled]", "15:00")
      book_at(lot, tomorrow, ~T[15:00:00])
      assert has_element?(view, "#slots button[disabled]", "15:00")
    end

    test "guests are asked to sign in before booking", %{conn: conn, lot: lot} do
      {:ok, view, _html} = live(conn, ~p"/lots/#{lot.id}")

      view
      |> element(
        "button[phx-click=pick_date]",
        Calendar.strftime(Date.add(today(lot), 1), "%d.%m")
      )
      |> render_click()

      view |> element("#slots button", "12:00") |> render_click()
      assert render(view) =~ "Sign in to book"
    end
  end

  describe "widgets on" do
    setup do
      admin = user(%{role: :admin})

      {:ok, _} =
        Basa.System.update_settings(Basa.System.settings(), %{widgets_enabled: true},
          actor: admin
        )

      :ok
    end

    test "the page has the calendar and gallery widgets", %{conn: conn, lot: lot} do
      {:ok, view, _html} = live(conn, ~p"/lots/#{lot.id}")

      assert has_element?(
               view,
               "#lot-calendar[phx-hook=Widget][data-component=AvailabilityCalendar]"
             )

      refute has_element?(view, "button[phx-click=pick_date]")

      [json] =
        view
        |> element("#lot-calendar")
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.attribute("data-props")

      assert %{"lotId" => id, "timezone" => "Europe/Kyiv", "readOnly" => false} =
               Jason.decode!(json)

      assert id == lot.id
    end

    test "a slot picked in the widget opens the booking", %{conn: conn, lot: lot} do
      {:ok, view, _html} = conn |> sign_in(user()) |> live(~p"/lots/#{lot.id}")
      assert pick(view, lot, Date.add(today(lot), 1), ~T[12:00:00]) =~ "Until"
    end

    test "packets the calendar doesn't send are refused", %{conn: conn, lot: lot} do
      {:ok, view, _html} = conn |> sign_in(user()) |> live(~p"/lots/#{lot.id}")

      html =
        render_hook(view, "widget:event", %{
          "widget" => "lot-calendar",
          "component" => "AvailabilityCalendar",
          "type" => "booking.create",
          "data" => %{}
        })

      refute html =~ "Until"
      refute render_hook(view, "widget:event", %{"nonsense" => 1}) =~ "Until"
    end

    test "the widget is told to reload when anyone books", %{conn: conn, lot: lot} do
      {:ok, view, _html} = live(conn, ~p"/lots/#{lot.id}")
      book_at(lot, Date.add(today(lot), 1), ~T[15:00:00])
      lot_id = lot.id

      assert_push_event(view, "widget:lot-calendar", %{
        type: "availability.changed",
        data: %{lotId: ^lot_id}
      })
    end

    test "the owner can't book their own offer", %{conn: conn, lot: lot, lessor: lessor} do
      {:ok, view, _html} = conn |> sign_in(lessor) |> live(~p"/lots/#{lot.id}")
      refute pick(view, lot, Date.add(today(lot), 1), ~T[12:00:00]) =~ "Until"
    end
  end

  defp pick(view, lot, date, time) do
    start = DateTime.new!(date, time, lot.timezone) |> DateTime.shift_zone!("Etc/UTC")

    render_hook(view, "widget:event", %{
      "widget" => "lot-calendar",
      "component" => "AvailabilityCalendar",
      "type" => "slot.picked",
      "data" => %{"startsAt" => DateTime.to_iso8601(start)}
    })
  end

  defp book_at(lot, date, time) do
    starts = DateTime.new!(date, time, lot.timezone) |> DateTime.shift_zone!("Etc/UTC")

    {:ok, _} =
      Basa.Bookings.book(
        %{lot_id: lot.id, starts_at: starts, ends_at: DateTime.add(starts, 3600)},
        actor: user()
      )
  end

  defp today(lot), do: DateTime.now!(lot.timezone) |> DateTime.to_date()
end
