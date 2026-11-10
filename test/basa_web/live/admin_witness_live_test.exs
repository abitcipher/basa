defmodule BasaWeb.AdminWitnessLiveTest do
  use BasaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Basa.Fixtures

  setup %{conn: conn} do
    lessor = user()
    lessee = user()

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

    {:ok, tx} = Basa.Witness.open_transaction(booking.id, %{}, actor: lessee)
    {:ok, _} = Basa.Witness.Store.add(tx, :photo, "image/jpeg", "a photo", lessee)
    admin = user(%{role: :admin})
    %{tx: tx, admin_conn: sign_in(conn, admin), lessor: lessor}
  end

  test "admins check all contracts, then one, and read its access log", ctx do
    {:ok, view, html} = live(ctx.admin_conn, ~p"/admin/witness")
    assert html =~ "Vocal session"

    view |> element("#check-all") |> render_click()
    assert render(view) =~ "Checked 1, failed 0."
    assert has_element?(view, "#contract-#{ctx.tx.id}", "ok")

    view |> element("#contract-#{ctx.tx.id} a") |> render_click()
    view |> element("#check-one") |> render_click()
    assert has_element?(view, "#check-result", "Everything checks out.")

    assert view |> element("#access-log") |> render() |> String.split("admin check") |> length() ==
             3
  end

  test "non-admins are sent away", %{conn: conn, lessor: lessor} do
    assert {:error, {:live_redirect, %{to: "/"}}} =
             conn |> sign_in(lessor) |> live(~p"/admin/witness")
  end
end
