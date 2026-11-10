defmodule BasaWeb.TelegramAppTest do
  use BasaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Basa.Fixtures

  test "the start screen has a tile for each main part", %{conn: conn} do
    {:ok, view, _} = conn |> sign_in(user(%{display_name: "Olena"})) |> live(~p"/app")
    assert has_element?(view, "#app-home", "Hi, Olena!")

    for {id, path} <- [
          {"find", "/"},
          {"bookings", "/bookings"},
          {"messages", "/messages"},
          {"offers", "/my"},
          {"schedule", "/my/schedule"},
          {"add", "/my/items/new"},
          {"profile", "/profile"},
          {"help", "/help"}
        ] do
      assert has_element?(view, ~s(a#tile-#{id}[href="#{path}"]))
    end
  end
end
