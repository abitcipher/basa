defmodule BasaWeb.InfoTipsTest do
  use BasaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Basa.Fixtures

  test "page notes are behind the i", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/verify")
    assert has_element?(view, "#verify-info [role=tooltip]", "not stored")
    assert has_element?(view, "#verify-info [role=button][aria-label]")

    {:ok, view, _} = conn |> sign_in(user()) |> live(~p"/my/photos")
    assert has_element?(view, "#photos-info [role=tooltip]", "Add new ones")
  end

  test "admin settings: section and service notes are behind the i", %{conn: conn} do
    {:ok, view, _} = conn |> sign_in(user(%{role: :admin})) |> live(~p"/admin/settings")

    assert has_element?(view, "#widgets-info [role=tooltip]", "simpler versions")
    assert has_element?(view, "#services-info [role=tooltip]", "can't guarantee")

    for s <- Basa.Services.all(),
        do: assert(has_element?(view, "#service-#{s}-info [role=tooltip]", "When off:"))
  end
end
