defmodule BasaWeb.HomeLiveTest do
  use BasaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Basa.Fixtures

  setup do
    lessor = user()
    odesa = geo_city("Odesa")
    room = room(lessor, %{city_id: odesa.id})
    basket = basket(lessor, [item(lessor)])
    cheap = published_lot(lessor, basket, room, %{title: "Cheap studio", price_amount: 300})
    dear = published_lot(lessor, basket, room, %{title: "Dear studio", price_amount: 900})
    %{cheap: cheap, dear: dear, odesa: odesa}
  end

  test "filters come from the URL and the form keeps them there", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/?price_max=500&currency=UAH")
    assert html =~ "Cheap studio"
    refute html =~ "Dear studio"
    assert has_element?(view, "#results-count", "1 offer")

    view
    |> form("#search-form", filters: %{price_max: "", sort: "price_desc", currency: "UAH"})
    |> render_change()

    assert_patch(view, ~p"/?currency=UAH&sort=price_desc")
    html = render(view)
    assert html =~ "Dear studio" and html =~ "Cheap studio"
    assert :binary.match(html, "Dear studio") < :binary.match(html, "Cheap studio")
  end

  test "clearing filters keeps the view", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/?price_max=1&currency=UAH&view=map")
    assert render(view) =~ "Try fewer filters"
    view |> element("button", "Clear filters") |> render_click()
    assert_patch(view, ~p"/?view=map")
  end

  test "the map view shows the results as markers and opens an offer", %{conn: conn, cheap: cheap} do
    {:ok, view, _} = live(conn, ~p"/")
    view |> element("#view-map") |> render_click()
    assert_patch(view, ~p"/?view=map")

    [json] =
      view
      |> element("#results-map")
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.attribute("data-markers")

    markers = Jason.decode!(json)
    assert length(markers) == 2

    assert %{"title" => "Cheap studio", "price" => "300.00 UAH / hour"} =
             Enum.find(markers, &(&1["id"] == cheap.id))

    assert {:error, {:live_redirect, %{to: to}}} =
             render_hook(view, "open_lot", %{"id" => cheap.id})

    assert to == "/lots/#{cheap.id}"
  end

  test "cards show the city in the page's language", %{conn: conn} do
    {:ok, _view, html} = conn |> get(~p"/?locale=uk") |> then(&live(&1, ~p"/"))
    assert html =~ "Одеса"
  end
end
