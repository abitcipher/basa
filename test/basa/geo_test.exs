defmodule Basa.GeoTest do
  use Basa.DataCase, async: false

  import Basa.Fixtures
  alias Basa.Geo
  alias Basa.Geo.Library

  @feature %{
    "type" => "Feature",
    "geometry" => %{"type" => "Point", "coordinates" => [-0.9101268, 41.6915847]},
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

  @lookup %{
    "osm_id" => 345_740,
    "namedetails" => %{
      "name" => "Zaragoza",
      "name:uk" => "Сарагоса",
      "name:de" => "Saragossa",
      "name:fr" => "Saragosse"
    },
    "extratags" => %{"population" => "699007"}
  }

  defp stub_osm(features \\ [@feature]) do
    Req.Test.stub(Basa.Geo.Photon, fn conn ->
      case conn.request_path do
        "/api" -> Req.Test.json(conn, %{"features" => features})
        "/lookup" -> Req.Test.json(conn, [@lookup])
      end
    end)
  end

  setup do
    :ets.delete_all_objects(:basa_geo_photon)
    %{odesa: geo_city("Odesa"), berlin: geo_city("Berlin"), madrid: geo_city("Madrid")}
  end

  describe "suggestions (Postgres, when Meilisearch is off)" do
    test "match the start of a name in any language", ctx do
      assert [%{id: id}] = Geo.suggest("ode")
      assert id == ctx.odesa.id
      assert [%{name: "Odesa"}] = Geo.suggest("Одес")
      assert [%{name: "Berlin"}] = Geo.suggest("берл")
      assert Geo.suggest("xyz") == []
    end

    test "no query: the most picked first, then the biggest", ctx do
      assert [%{name: "Berlin"}, %{name: "Madrid"}, %{name: "Odesa"}] = Geo.suggest("")
      {:ok, _} = Geo.picked(ctx.odesa)
      assert [%{name: "Odesa"} | _] = Geo.suggest("")
    end

    test "nearest city and names" do
      assert Geo.nearest(46.4, 30.7).name == "Odesa"
      assert Geo.find_by_name("одеса").name == "Odesa"

      assert Basa.Geo.City.label(Geo.find_by_name("Berlin"), "uk") ==
               "Берлін, Німеччина"
    end
  end

  describe "OpenStreetMap" do
    test "a lessor's pick adds the city with our languages and a time zone" do
      stub_osm()
      assert [cand] = Geo.external("Zarag", "en")
      assert cand.id == "osm:R345740"

      {:ok, city} = Geo.add_candidate(cand, :lessor)
      assert city.names["uk"] == "Сарагоса"
      assert city.population == 699_007
      assert city.timezone == "Europe/Madrid"
      assert city.raw["photon"]["properties"]["osm_id"] == 345_740
      assert city.raw["nominatim"]["namedetails"]["name:fr"] == "Saragosse"

      assert Geo.external("Zarag", "en") == []
      assert [%{id: "osm:R345740"}] = Geo.suggest("zarag")
    end

    test "searches for a missing city add up per place, and admins add it" do
      stub_osm()
      {:ok, _} = Geo.record_miss("Zarago")
      :ets.delete_all_objects(:basa_geo_photon)
      {:ok, _} = Geo.record_miss("Saragossa")

      admin = user(%{role: :admin})

      assert [%{id: "osm:R345740", count: 2, query: "Saragossa"} = wanted] =
               Geo.list_demand!(actor: admin)

      assert {:ok, []} = Geo.list_demand(actor: user())

      {:ok, city} = Geo.add_wanted(wanted, admin)
      assert city.origin == :admin
      assert [%{status: :added}] = Geo.list_demand!(actor: admin)
    end

    test "places we already have, or that aren't settlements, are left out" do
      odesa_osm =
        @feature
        |> put_in(["geometry", "coordinates"], [30.7233, 46.4825])
        |> update_in(
          ["properties"],
          &Map.merge(&1, %{"osm_id" => 1, "name" => "Одеса", "countrycode" => "UA"})
        )

      hromada =
        put_in(odesa_osm, ["properties", "osm_value"], "municipality")
        |> put_in(["properties", "osm_id"], 2)

      moscow =
        update_in(@feature["properties"], &Map.merge(&1, %{"osm_id" => 3, "countrycode" => "RU"}))

      stub_osm([odesa_osm, hromada, moscow, @feature])
      assert [%{id: "osm:R345740"}] = Geo.external("Оде", "uk")
    end

    test "a query OpenStreetMap doesn't know is counted by its text" do
      stub_osm([])
      {:ok, d} = Geo.record_miss("Atlantis")
      assert d.id == "q:atlantis"
      assert Geo.record_miss("ab") == :ok
    end
  end

  describe "rooms" do
    test "a picked city names the room and ranks higher", ctx do
      lessor = user()
      room = room(lessor, %{city_id: ctx.berlin.id, city: "whatever"})
      assert room.city == "Berlin"
      assert Geo.get(ctx.berlin.id).picks == 1

      assert {:error, _} =
               Basa.Catalog.create_room(%{title: "X", city_id: "gn:0", lat: 1.0, lng: 1.0},
                 actor: lessor
               )
    end

    test "a room with only a city name gets the city's id", ctx do
      assert room(user(), %{city: "odesa"}).city_id == ctx.odesa.id
      assert room(user(), %{city: "Nowhere"}).city_id == nil
    end

    test "older rooms are linked when their city arrives" do
      room = room(user(), %{city: "Lviv"})
      assert room.city_id == nil
      lviv = geo_city("Lviv")
      assert Library.link_rooms() == 1
      assert Ash.reload!(room, authorize?: false).city_id == lviv.id
    end
  end

  describe "backup" do
    test "export and restore keep picks, added cities and demand", ctx do
      stub_osm()
      {:ok, _} = Geo.picked(ctx.madrid)
      {:ok, _} = Geo.record_miss("Zaragoza")
      path = Path.join(System.tmp_dir!(), "geo-#{System.unique_integer([:positive])}.jsonl.gz")
      on_exit(fn -> File.rm(path) end)

      assert {:ok, %{cities: 3, demand: 1}} = Library.export(path)

      Basa.Repo.query!("DELETE FROM geo_demand")
      Basa.Repo.query!("UPDATE geo_cities SET picks = 0, names = '{}'")
      assert {:ok, %{cities: 3, demand: 1}} = Library.restore(path)

      assert Geo.get(ctx.madrid.id).picks == 1
      assert Geo.get(ctx.odesa.id).names["uk"] == "Одеса"
      assert [%{count: 1}] = Geo.list_demand!(actor: user(%{role: :admin}))
    end

    test "the shipped seed loads the pilot cities and keeps picks", ctx do
      {:ok, _} = Geo.picked(ctx.odesa)
      n = Library.import_seed()
      assert n > 500
      assert Geo.get("gn:698740").picks == 1
      assert Enum.all?(["Kyiv", "Paris", "Lisbon", "Porto", "Barcelona"], &Geo.find_by_name/1)
      assert Geo.find_by_name("Київ").timezone == "Europe/Kyiv"
    end
  end
end
