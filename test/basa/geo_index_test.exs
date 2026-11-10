defmodule Basa.Geo.IndexTest do
  use Basa.DataCase, async: false

  import Basa.Fixtures

  @url "http://localhost:7700"
  @key "basa-dev-master-key-change-me"

  setup do
    previous = Application.get_env(:basa, Basa.Search)
    index = "cities_test_#{System.unique_integer([:positive])}"
    Application.put_env(:basa, Basa.Search, url: @url, key: @key, cities_index: index)

    on_exit(fn ->
      Req.delete("#{@url}/indexes/#{index}", auth: {:bearer, @key}, retry: false)
      Application.put_env(:basa, Basa.Search, previous || [])
    end)

    case Req.get("#{@url}/health", retry: false) do
      {:ok, %{status: 200}} -> :ok
      _ -> {:skip, :meilisearch_not_running}
    end
  end

  test "typos and other languages find the city; picks break ties" do
    geo_city("Odesa")
    geo_city("Berlin")
    geo_city("Madrid")

    geo_city("Bern", %{
      country_code: "CH",
      population: 134_000,
      names: %{"en" => "Bern", "de" => "Bern"}
    })

    assert Basa.Geo.Index.reindex_all() == 4
    Basa.Geo.Index.wait_idle()

    assert [%{name: "Berlin"} | _] = Basa.Geo.suggest("berlni")
    assert [%{name: "Odesa"} | _] = Basa.Geo.suggest("Одеса")
    assert [%{name: "Madrid"} | _] = Basa.Geo.suggest("madird")
    geo_city("Нова Одеса", %{population: 12_410})
    Basa.Geo.Index.reindex_all()
    Basa.Geo.Index.wait_idle()
    assert [%{name: "Odesa"}, %{name: "Нова Одеса"}] = Basa.Geo.suggest("одес")
    geo_city("Kiel", %{country_code: "DE", population: 246_000})
    geo_city("Kielce", %{country_code: "PL", population: 1_900_000})
    Basa.Geo.Index.reindex_all()
    Basa.Geo.Index.wait_idle()
    assert [%{name: "Kiel"}, %{name: "Kielce"}] = Basa.Geo.suggest("kiel")

    assert [%{name: "Berlin"}, %{name: "Bern"}] = Basa.Geo.suggest("Ber")

    bern = Basa.Geo.find_by_name("Bern")
    for _ <- 1..3, do: {:ok, _} = Basa.Geo.picked(Ash.reload!(bern, authorize?: false))
    :ok = Basa.Geo.Index.put([Ash.reload!(bern, authorize?: false)])
    Basa.Geo.Index.wait_idle()
    assert [%{name: "Bern"}, %{name: "Berlin"}] = Basa.Geo.suggest("Ber")
  end
end
