defmodule Basa.Geo.Library do
  alias Basa.Geo.{City, Demand, Index}

  @seed "priv/geo/cities.json.gz"
  @city_keys ~w(id source origin name names ascii_name country_code admin1 lat lng timezone population picks raw)a
  @demand_keys ~w(id label country_code query candidate count status last_searched_at)a

  def import_seed do
    path = Application.app_dir(:basa, @seed)

    count =
      path
      |> File.read!()
      |> :zlib.gunzip()
      |> Jason.decode!()
      |> Enum.map(&Map.put(&1, "origin", "seed"))
      |> load(City, :import)

    link_rooms()
    Index.reindex_all()
    count
  end

  def export(path) do
    File.mkdir_p!(Path.dirname(path))
    cities = Ash.read!(City, authorize?: false)
    demand = Ash.read!(Demand, authorize?: false)

    lines =
      [Jason.encode!(%{type: "basa.geo", version: 1, exported_at: DateTime.utc_now()})] ++
        Enum.map(cities, &Jason.encode!(Map.put(Map.take(&1, @city_keys), :type, "city"))) ++
        Enum.map(demand, &Jason.encode!(Map.put(Map.take(&1, @demand_keys), :type, "demand")))

    File.write!(path, :zlib.gzip(Enum.intersperse(lines, "\n")))
    {:ok, %{cities: length(cities), demand: length(demand)}}
  end

  def restore(path) do
    [meta | rows] =
      path
      |> File.read!()
      |> :zlib.gunzip()
      |> String.split("\n", trim: true)
      |> Enum.map(&Jason.decode!/1)

    %{"type" => "basa.geo", "version" => 1} = meta
    by_type = Enum.group_by(rows, & &1["type"], &Map.delete(&1, "type"))

    cities = load(by_type["city"] || [], City, :restore)
    demand = load(by_type["demand"] || [], Demand, :restore)
    link_rooms()
    Index.reindex_all()
    {:ok, %{cities: cities, demand: demand}}
  end

  def link_rooms do
    {:ok, %{num_rows: n}} =
      Basa.Repo.query("""
      UPDATE rooms r SET city_id = (
        SELECT c.id FROM geo_cities c
        WHERE lower(c.name) = lower(r.city) OR lower(c.ascii_name) = lower(r.city)
           OR EXISTS (SELECT 1 FROM jsonb_each_text(c.names) v WHERE lower(v.value) = lower(r.city))
        ORDER BY c.picks DESC, c.population DESC LIMIT 1)
      WHERE r.city_id IS NULL
        AND EXISTS (SELECT 1 FROM geo_cities c
                    WHERE lower(c.name) = lower(r.city) OR lower(c.ascii_name) = lower(r.city)
                       OR EXISTS (SELECT 1 FROM jsonb_each_text(c.names) v WHERE lower(v.value) = lower(r.city)))
      """)

    if n > 0, do: Basa.Search.reindex_all()
    n
  end

  defp load([], _resource, _action), do: 0

  defp load(rows, resource, action) do
    rows
    |> Enum.chunk_every(500)
    |> Enum.reduce(0, fn chunk, acc ->
      %Ash.BulkResult{status: :success} =
        Ash.bulk_create(chunk, resource, action,
          authorize?: false,
          context: %{skip_reindex: true},
          return_errors?: true,
          stop_on_error?: true
        )

      acc + length(chunk)
    end)
  end
end
