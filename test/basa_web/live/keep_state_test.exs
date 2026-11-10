defmodule BasaWeb.KeepStateTest do
  use BasaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Basa.Fixtures

  alias BasaWeb.KeepState

  defp token(view, id) do
    view |> element("##{id}") |> render() |> token_in()
  end

  defp token_in(html) do
    [token] = html |> Floki.parse_fragment!() |> Floki.attribute("data-token")
    token
  end

  defp socket(user),
    do: %Phoenix.LiveView.Socket{assigns: %{__changed__: %{}, current_user: user}}

  describe "kept state" do
    test "opens only for the same user, page and starting point" do
      owner = user()
      socket = KeepState.start(socket(owner), "lot-wizard:new", %{"title" => ""})

      html =
        render_component(&KeepState.kept/1,
          keep: socket.assigns.keep,
          data: {2, %{"title" => "Amp"}}
        )

      token = token_in(html)

      assert {:ok, {2, %{"title" => "Amp"}}} = KeepState.restore(socket, token)

      assert :error =
               KeepState.restore(
                 KeepState.start(socket(user()), "lot-wizard:new", %{"title" => ""}),
                 token
               )

      assert :error =
               KeepState.restore(
                 KeepState.start(socket(owner), "room-wizard:new", %{"title" => ""}),
                 token
               )

      assert :error =
               KeepState.restore(
                 KeepState.start(socket(owner), "lot-wizard:new", %{"title" => "x"}),
                 token
               )

      assert :error = KeepState.restore(socket, "forged")
    end
  end

  test "a wizard comes back at the same step with what was entered", %{conn: conn} do
    lessor = user()
    item(lessor, %{title: "Shure SM7B"})
    conn = sign_in(conn, lessor)

    {:ok, view, _} = live(conn, ~p"/my/baskets/new")
    view |> form("form[phx-submit=details]", basket: %{title: "Podcast kit"}) |> render_submit()
    view |> element("button[phx-click=toggle]", "Shure SM7B") |> render_click()
    view |> element("button[phx-click=goto]", "Next") |> render_click()
    assert has_element?(view, "button", "Save basket")
    token = token(view, "keep-basket-wizard-new")

    {:ok, view, _} = live(conn, ~p"/my/baskets/new")
    refute has_element?(view, "button", "Save basket")
    render_hook(view, "keep:restore", %{"token" => token})
    assert_reply(view, %{ok: true})
    assert has_element?(view, "button", "Save basket")

    assert {:error, {:live_redirect, %{to: "/my"}}} =
             view |> element("button", "Save basket") |> render_click()

    assert_push_event(view, "keep:forget", %{key: "basket-wizard:new"})

    [basket] = Basa.Catalog.list_my_baskets!(actor: lessor, load: [:items])
    assert basket.title == "Podcast kit"
    assert [%{title: "Shure SM7B"}] = basket.items

    {:ok, other, _} = conn |> recycle() |> sign_in(user()) |> live(~p"/my/baskets/new")
    render_hook(other, "keep:restore", %{"token" => token})
    assert_reply(other, %{ok: false})
    refute has_element?(other, "button", "Save basket")
  end
end
