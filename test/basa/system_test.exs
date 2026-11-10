defmodule Basa.SystemTest do
  use BasaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Basa.Fixtures

  test "settings start from the configured default; only admins change them" do
    settings = Basa.System.settings()
    refute settings.widgets_enabled
    assert Basa.System.settings().id == settings.id

    assert {:error, %Ash.Error.Forbidden{}} =
             Basa.System.update_settings(settings, %{widgets_enabled: true}, actor: user())

    admin = user(%{role: :admin})
    {:ok, on} = Basa.System.update_settings(settings, %{widgets_enabled: true}, actor: admin)
    assert on.widgets_enabled and on.updated_by_email == to_string(admin.email)
    assert Basa.System.widgets_enabled?()
  end

  test "the admin page switches widgets for pages opened afterwards", %{conn: conn} do
    lessor = user()
    lot = published_lot(lessor, basket(lessor, [item(lessor)]), room(lessor))

    {:ok, page, _} = live(conn, ~p"/lots/#{lot.id}")
    refute has_element?(page, "[phx-hook=Widget]")

    {:ok, view, _} = conn |> sign_in(user(%{role: :admin})) |> live(~p"/admin/settings")
    view |> element("#widgets-toggle") |> render_click()

    {:ok, page, _} = live(build_conn(), ~p"/lots/#{lot.id}")
    assert has_element?(page, "[phx-hook=Widget]")
  end

  test "non-admins can't open the settings page", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/"}}} =
             conn |> sign_in(user()) |> live(~p"/admin/settings")
  end
end
