defmodule BasaWeb.AdminDataLiveTest do
  use BasaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Basa.Fixtures

  setup do
    lessor = user(%{display_name: "Lessor Lena"})

    lot =
      published_lot(lessor, basket(lessor, [item(lessor)]), room(lessor), %{
        title: "Vocal session"
      })

    starts = hours_from_now(30)

    {:ok, _} =
      Basa.Bookings.book(
        %{lot_id: lot.id, starts_at: starts, ends_at: DateTime.add(starts, 3600)},
        actor: user(%{display_name: "Lessee Lev"})
      )

    %{admin: user(%{role: :admin}), lessor: lessor}
  end

  test "admin reads: every booking with readable columns, admins only", ctx do
    assert [b] =
             Basa.Bookings.Booking
             |> Ash.Query.for_read(:admin_list, %{}, actor: ctx.admin)
             |> Ash.Query.load([:lot_title, :lessor_name, :lessee_name])
             |> Ash.read!()

    assert {b.lot_title, b.lessor_name, b.lessee_name} ==
             {"Vocal session", "Lessor Lena", "Lessee Lev"}

    for resource <- [Basa.Bookings.Booking, Basa.Accounts.User, Basa.Payments.Payment] do
      assert {:ok, []} =
               resource |> Ash.Query.for_read(:admin_list, %{}, actor: ctx.lessor) |> Ash.read()
    end
  end

  test "widgets off: the latest rows per table", %{conn: conn, admin: admin} do
    {:ok, view, html} = conn |> sign_in(admin) |> live(~p"/admin/data")
    assert html =~ "Lessor Lena"

    view |> element("#kind-bookings") |> render_click()
    assert has_element?(view, "#admin-table", "Vocal session")
    assert has_element?(view, "#admin-table", "Lessee Lev")
  end

  test "widgets on: the grid; non-admins are sent away", %{
    conn: conn,
    admin: admin,
    lessor: lessor
  } do
    {:ok, _} =
      Basa.System.update_settings(Basa.System.settings(), %{widgets_enabled: true}, actor: admin)

    {:ok, view, _} = conn |> sign_in(admin) |> live(~p"/admin/data?kind=payments")
    assert has_element?(view, "#admin-grid-payments[data-component=AdminGrid]")

    assert {:error, {:live_redirect, %{to: "/"}}} =
             conn |> sign_in(lessor) |> live(~p"/admin/data")
  end
end
