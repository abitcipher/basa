defmodule BasaWeb.CityPickerTest do
  use BasaWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Basa.Fixtures

  setup do
    Req.Test.set_req_test_to_shared()
    :ets.delete_all_objects(:basa_geo_photon)

    Req.Test.stub(Basa.Geo.Photon, fn conn ->
      case conn.request_path do
        "/api" ->
          Req.Test.json(conn, %{
            "features" => [
              %{
                "geometry" => %{"coordinates" => [-0.91, 41.69]},
                "properties" => %{
                  "osm_type" => "R",
                  "osm_id" => 345_740,
                  "name" => "Zaragoza",
                  "countrycode" => "ES",
                  "state" => "Aragon",
                  "osm_key" => "place",
                  "osm_value" => "city"
                }
              }
            ]
          })

        "/lookup" ->
          Req.Test.json(conn, [%{"namedetails" => %{"name:uk" => "Сарагоса"}, "extratags" => %{}}])
      end
    end)

    on_exit(fn -> Req.Test.set_req_test_to_private() end)
    %{berlin: geo_city("Berlin"), madrid: geo_city("Madrid")}
  end

  test "a lessor picks a city for a new room", %{conn: conn, berlin: berlin} do
    lessor = user()
    {:ok, view, _} = conn |> sign_in(lessor) |> live(~p"/my/rooms/new")

    view |> form("#room-form", room: %{title: "Loft"}) |> render_change()
    html = view |> element("#room-city-input") |> render_change(%{"room-city_q" => "berl"})
    assert html =~ "State of Berlin"

    view |> element("#room-city-list button", "Berlin") |> render_click()
    assert view |> element("#room-city input[type=hidden]") |> render() =~ berlin.id

    view |> form("#room-form") |> render_submit()
    assert [room] = Basa.Catalog.list_my_rooms!(actor: lessor)
    assert room.city_id == berlin.id and room.city == "Berlin"
    assert_in_delta room.lat, berlin.lat, 0.001
  end

  test "a lessor can add a city from OpenStreetMap", %{conn: conn} do
    {:ok, view, _} = conn |> sign_in(user()) |> live(~p"/my/rooms/new")

    html = view |> element("#room-city-input") |> render_change(%{"room-city_q" => "Zarago"})
    assert html =~ "OpenStreetMap"

    view |> element("#room-city-list button", "Zaragoza") |> render_click()
    city = Basa.Geo.get("osm:R345740")
    assert city.origin == :lessor and city.timezone == "Europe/Madrid"
    assert view |> element("#room-city input[type=hidden]") |> render() =~ "osm:R345740"
  end

  test "lessees only get cities BASA has; a miss is counted once", %{conn: conn, madrid: madrid} do
    {:ok, view, _} = live(conn, ~p"/")

    html =
      view |> element("#filters-city-input") |> render_change(%{"filters-city_q" => "Zarago"})

    assert html =~ "No offers in this city yet"
    refute html =~ "OpenStreetMap"

    view |> element("#filters-city-input") |> render_change(%{"filters-city_q" => "Zaragoza"})
    view |> with_target("#filters-city") |> render_hook("close", %{})
    assert [%{count: 1, query: "Zaragoza"}] = Basa.Geo.list_demand!(actor: user(%{role: :admin}))

    view |> element("#filters-city-input") |> render_change(%{"filters-city_q" => "madr"})
    view |> element("#filters-city-list button", "Madrid") |> render_click()
    assert_patch(view, ~p"/?#{%{city: madrid.id}}")
  end

  test "admins see wanted places and add them", %{conn: conn} do
    {:ok, _} = Basa.Geo.record_miss("Zaragoza")
    {:ok, view, html} = conn |> sign_in(user(%{role: :admin})) |> live(~p"/admin/geo")
    assert html =~ "Zaragoza, Aragon, ES"

    view |> element("button", "Add") |> render_click()
    assert Basa.Geo.get("osm:R345740").origin == :admin
  end
end
