defmodule BasaWeb.SalesLiveTest do
  use BasaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Basa.Fixtures

  setup do
    seller = user()
    room = room(seller)
    mic = item(seller, %{title: "Neumann U87", estimated_value: 120_000})
    basket = basket(seller, [mic])
    %{seller: seller, room: room, basket: basket}
  end

  test "the wizard sells: price is the items' value, no unit, a sale lot", %{conn: conn} = ctx do
    {:ok, view, _} = conn |> sign_in(ctx.seller) |> live(~p"/my/lots/new")
    view |> element("button[phx-click=goto]", "Next") |> render_click()
    view |> element("button[phx-click=pick_deal]", "Sell") |> render_click()
    refute has_element?(view, "button[phx-click=pick_unit]")
    for _ <- 1..2, do: view |> element("button[phx-click=goto]", "Next") |> render_click()
    assert render(view) =~ "120000"

    {:error, {:live_redirect, _}} =
      view |> element("button[phx-value-publish=true]") |> render_click()

    [lot] = Basa.Catalog.list_my_lots!(actor: ctx.seller)
    assert {lot.deal, lot.price_amount} == {:sale, Decimal.new(120_000)}
  end

  test "search tells rent from buy; the lot page speaks of buying", %{conn: conn} = ctx do
    sale =
      published_lot(ctx.seller, ctx.basket, ctx.room, %{title: "Neumann for sale", deal: :sale})

    published_lot(ctx.seller, basket(ctx.seller, [item(ctx.seller)]), ctx.room, %{
      title: "Studio for rent"
    })

    {:ok, view, html} = live(conn, ~p"/?deal=sale")
    assert html =~ "Neumann for sale" and html =~ "For sale"
    refute html =~ "Studio for rent"

    {:ok, _, html} = live(conn, ~p"/?deal=lease")
    assert html =~ "Studio for rent"
    refute html =~ "Neumann for sale"
    _ = view

    {:ok, _, html} = live(conn, ~p"/lots/#{sale.id}")
    assert html =~ "Pick a handover time" and html =~ "For sale"
  end
end
