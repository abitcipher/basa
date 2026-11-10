defmodule BasaWeb.AppearanceLiveTest do
  use BasaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Basa.Fixtures

  alias Basa.Accounts.UiPrefs

  test "preferences: only known values, sizes kept in range" do
    assert UiPrefs.normalize(%{
             "style" => "black",
             "action" => "pink",
             "button" => "500",
             "icon" => 10,
             "x" => 1
           }) ==
             %{"style" => "black", "button" => 130, "icon" => 80}

    assert UiPrefs.get(nil) == UiPrefs.defaults()
    assert UiPrefs.get(%{ui: %{"nav" => "orange"}})["nav"] == "orange"
  end

  test "every page carries the preferences; defaults for guests", %{conn: conn} do
    html = conn |> get(~p"/") |> html_response(200)
    assert html =~ ~s(data-btn-style="brand") and html =~ "--ui-btn-scale:1.0"
    assert html =~ ~s(id="app-main" data-glow="on")
  end

  test "changes are saved, applied at once, and shown on the next page", %{conn: conn} do
    user = user()
    conn = sign_in(conn, user)
    {:ok, view, _} = live(conn, ~p"/appearance")

    view
    |> form("#appearance-form",
      ui: %{
        style: "black",
        action: "orange",
        nav: "green",
        disabled: "gray",
        button: "90",
        icon: "120",
        text: "110"
      },
      glow: "false"
    )
    |> render_change()

    assert_push_event(view, "ui:apply", %{attrs: %{"data-btn-style" => "black"}, glow: "off"})

    user = Ash.reload!(user, authorize?: false)

    assert user.ui == %{
             "style" => "black",
             "action" => "orange",
             "nav" => "green",
             "disabled" => "gray",
             "button" => 90,
             "icon" => 120,
             "text" => 110
           }

    refute user.glow

    html = conn |> get(~p"/bookings") |> html_response(200)
    assert html =~ ~s(data-btn-action="orange") and html =~ "--ui-icon-scale:1.2"
    assert html =~ ~s(data-glow="off")

    view |> element("button", "Back to defaults") |> render_click()
    assert Ash.reload!(user, authorize?: false).ui == UiPrefs.defaults()
  end
end
