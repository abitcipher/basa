defmodule BasaWeb.LessorFlowTest do
  use BasaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Basa.Fixtures

  test "lessor pages require sign-in", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/sign-in"}}} = live(conn, ~p"/my")
  end

  test "items form shows the category's schema fields and saves typed attributes", %{conn: conn} do
    lessor = user()

    category =
      category(%{
        attr_schema: %{
          "type" => "object",
          "properties" => %{"channels" => %{"type" => "integer", "title" => "Channels"}}
        }
      })

    {:ok, view, _} = conn |> sign_in(lessor) |> live(~p"/my/items/new")

    view
    |> form("#item-form", item: %{title: "Yamaha MG10", category_id: category.id})
    |> render_change()

    assert has_element?(view, "input[name='item[attrs][channels]']")

    view
    |> form("#item-form",
      item: %{title: "Yamaha MG10", category_id: category.id, attrs: %{channels: "10"}}
    )
    |> render_submit()

    [item] = Basa.Catalog.list_my_items!(actor: lessor)
    assert item.attrs == %{"channels" => 10}
  end

  test "basket, then lot wizard publishes an offer", %{conn: conn} do
    lessor = user()
    item(lessor, %{title: "Shure SM7B"})
    room(lessor)
    conn = sign_in(conn, lessor)

    {:ok, view, _} = live(conn, ~p"/my/baskets/new")
    view |> form("form[phx-submit=details]", basket: %{title: "Podcast kit"}) |> render_submit()
    view |> element("button[phx-click=toggle]", "Shure SM7B") |> render_click()
    view |> element("button[phx-click=goto]", "Next") |> render_click()

    assert {:error, {:live_redirect, %{to: "/my"}}} =
             view |> element("button", "Save basket") |> render_click()

    {:ok, view, _} = live(conn, ~p"/my/lots/new")
    for _ <- 1..3, do: view |> element("button[phx-click=goto]", "Next") |> render_click()

    assert {:error, {:live_redirect, %{to: "/my"}}} =
             view |> element("button[phx-value-publish=true]") |> render_click()

    [lot] = Basa.Catalog.list_my_lots!(actor: lessor)
    assert lot.state == :published
  end
end
