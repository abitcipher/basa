defmodule Basa.Geo.Index do
  alias Basa.Search

  def index_name, do: Application.get_env(:basa, Basa.Search, [])[:cities_index] || "cities"

  def city_ids(q, opts \\ []) do
    filter = if c = opts[:country_code], do: ["country_code = #{Search.quote_value(c)}"], else: []
    body = %{q: q, limit: opts[:limit] || 8, attributesToRetrieve: ["ref"], filter: filter}

    case Search.enabled?() && Search.request(:post, "/indexes/#{index_name()}/search", body) do
      {:ok, %{status: 200, body: %{"hits" => hits}}} -> Enum.map(hits, & &1["ref"])
      _ -> :unavailable
    end
  end

  def setup do
    if Search.enabled?() do
      Search.request(:post, "/indexes", %{uid: index_name(), primaryKey: "id"})

      Search.request(:patch, "/indexes/#{index_name()}/settings", %{
        searchableAttributes: ["names", "admin1", "country"],
        filterableAttributes: ["country_code"],
        sortableAttributes: ["picks", "population"],
        rankingRules: [
          "words",
          "typo",
          "proximity",
          "exactness",
          "picks:desc",
          "population:desc",
          "attribute",
          "sort"
        ],
        typoTolerance: %{minWordSizeForTypos: %{oneTypo: 4, twoTypos: 7}}
      })

      :ok
    end
  end

  def put([]), do: :ok

  def put(cities) do
    case Search.request(
           :post,
           "/indexes/#{index_name()}/documents?primaryKey=id",
           Enum.map(cities, &document/1)
         ) do
      {:ok, %{status: s}} when s in 200..299 -> :ok
      {:ok, resp} -> {:error, {:http, resp.status}}
      {:error, reason} -> {:error, reason}
    end
  end

  def reindex_all do
    cities = Ash.read!(Basa.Geo.City, authorize?: false)

    if Search.enabled?() do
      setup()
      Search.request(:delete, "/indexes/#{index_name()}/documents", nil)
      cities |> Enum.chunk_every(1000) |> Enum.each(&(:ok = put(&1)))
    end

    length(cities)
  end

  def wait_idle(timeout \\ 10_000), do: Search.wait_idle(timeout, index_name())

  def document(city) do
    country = Basa.Geo.Countries.get(city.country_code)

    %{
      id: String.replace(city.id, ":", "-"),
      ref: city.id,
      name: city.name,
      names: Enum.uniq([city.name, city.ascii_name | Map.values(city.names || %{})] -- [nil]),
      ascii_name: city.ascii_name,
      admin1: city.admin1,
      country:
        if(country, do: Enum.uniq([country["name"] | Map.values(country["names"])]), else: []),
      country_code: city.country_code,
      population: city.population || 0,
      picks: city.picks
    }
  end
end
