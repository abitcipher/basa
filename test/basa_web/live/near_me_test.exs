defmodule BasaWeb.NearMeTest do
  use BasaWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Basa.Fixtures

  @odesa_point "lat=46.4825&lng=30.7233"

  setup do
    lessor = user()
    odesa = geo_city("Odesa", %{admin1: "17"})

    chornomorsk =
      geo_city("Chornomorsk", %{lat: 46.3017, lng: 30.6569, admin1: "17", population: 60_000})

    kyiv = geo_city("Kyiv", %{lat: 50.45, lng: 30.52, admin1: "12"})
    basket = basket(lessor, [item(lessor)])

    for {city, title, lat, lng} <- [
          {odesa, "Odesa studio", 46.4825, 30.7233},
          {chornomorsk, "Seaside studio", 46.3017, 30.6569},
          {kyiv, "Kyiv studio", 50.45, 30.52}
        ] do
      room = room(lessor, %{city_id: city.id, city: city.name, lat: lat, lng: lng})
      published_lot(lessor, basket, room, %{title: title})
    end

    %{odesa: odesa}
  end

  test "no distance control until there is a where", %{conn: conn} do
    {:ok, view, html} = live(conn, "/")
    refute has_element?(view, "#near-radius")
    assert html =~ "Kyiv studio"
  end

  test "a picked city: the whole city first, then distances from its centre", %{
    conn: conn,
    odesa: odesa
  } do
    {:ok, view, html} = live(conn, "/?city=#{odesa.id}")
    assert html =~ "Odesa studio"
    refute html =~ "Seaside studio"
    assert has_element?(view, "#near-radius-now", "Whole city: Odesa")
    refute has_element?(view, "#near-radius-value")
    assert has_element?(view, "#near-radius-info", "How far to search")

    {:ok, view, html} = live(conn, "/?city=#{odesa.id}&radius=75")
    assert html =~ "Odesa studio" and html =~ "Seaside studio"
    refute html =~ "Kyiv studio"
    assert has_element?(view, "#near-radius-now", "Within 75 km of Odesa")

    {:ok, _view, html} = live(conn, "/?city=#{odesa.id}&radius=region")
    assert html =~ "Odesa studio" and html =~ "Seaside studio"
    refute html =~ "Kyiv studio"
  end

  test "the location button: distances from the lessee", %{conn: conn, odesa: odesa} do
    {:ok, view, _html} = live(conn, "/")

    view
    |> with_target("#filters-city")
    |> render_hook("near", %{"lat" => 46.4825, "lng" => 30.7233})

    assert_patch(view, "/?city=#{URI.encode_www_form(odesa.id)}&lat=46.4825&lng=30.7233")

    assert has_element?(view, "#filters-city-near-me[aria-pressed=true]")
    assert has_element?(view, "#near-radius-now", "Within 25 km of you")
    assert has_element?(view, "#near-radius-slider[value='2']")

    view |> form("#search-form", filters: %{radius_step: "0"}) |> render_change()
    html = render(view)
    assert html =~ "Odesa studio"
    refute html =~ "Seaside studio"

    view |> element("#filters-city button[phx-click=clear]") |> render_click()
    refute has_element?(view, "#near-radius")
  end

  test "when the location fails, the picker says why and what still works", %{
    conn: conn,
    odesa: odesa
  } do
    {:ok, view, _html} = live(conn, "/")

    assert view
           |> with_target("#filters-city")
           |> render_hook("geo_error", %{"reason" => "denied"}) =~
             "site settings"

    assert render(view) =~ "Type the city instead"

    {:ok, view, _html} = live(conn, "/?city=#{odesa.id}")

    html =
      view
      |> with_target("#filters-city")
      |> render_hook("geo_error", %{"reason" => "unavailable"})

    assert html =~ "location services may be off"
    assert html =~ "The search stays around the chosen city"
  end

  test "an admin sets the control and the steps", %{conn: conn} do
    admin = user(%{role: :admin})
    conn = sign_in(conn, admin)
    {:ok, view, _html} = live(conn, ~p"/admin/settings")

    view
    |> form("#near-form",
      near: %{control: "chips", steps: "2, 5, 20", city: "false", region: "false", default: "25"}
    )
    |> render_submit()

    assert has_element?(view, "#near-error")
    assert has_element?(view, "#near-steps[value='2, 5, 20']")
    assert Basa.System.settings().near_control == :slider

    view
    |> form("#near-form",
      near: %{control: "chips", steps: "20, 2, x, 5", city: "true", region: "false", default: "5"}
    )
    |> render_submit()

    settings = Basa.System.settings()
    assert settings.near_control == :chips
    assert settings.near_steps_km == [2, 5, 20]
    assert Basa.System.near_steps(settings) == ["2", "5", "20", "city"]

    {:ok, view, _html} =
      live(conn, "/?#{@odesa_point}&city=#{Basa.Geo.nearest(46.4825, 30.7233).id}&radius=125")

    assert has_element?(view, "#near-radius input[value='5'][checked]")
    refute has_element?(view, "#near-radius input[value='region']")
  end
end
