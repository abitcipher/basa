defmodule Basa.Geo.Photon do
  use GenServer

  @table :basa_geo_photon
  @ttl :timer.hours(24)
  @langs Basa.I18n.codes()

  @type candidate :: %{
          id: String.t(),
          name: String.t(),
          country_code: String.t() | nil,
          admin1: String.t() | nil,
          lat: float(),
          lng: float(),
          feature: map()
        }

  def start_link(_), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @impl true
  def init(nil) do
    :ets.new(@table, [:named_table, :public, read_concurrency: true])
    {:ok, nil}
  end

  def configured?, do: Keyword.get(config(), :enabled, true)

  def enabled?, do: configured?() and Basa.Services.on?(:osm)

  @spec search(String.t(), String.t()) :: {:ok, [candidate()]} | {:error, term()}
  def search(q, lang \\ "en") do
    q = String.trim(q)
    key = {:search, String.downcase(q), lang}

    with :miss <- cached(key),
         true <- enabled?() || {:error, :disabled},
         {:ok, %{status: 200, body: %{"features" => features}}} <-
           get(config()[:photon_url] || "https://photon.komoot.io", "/api",
             q: q,
             limit: 6,
             lang: photon_lang(lang),
             layer: "city"
           ) do
      candidates = features |> Enum.map(&candidate/1) |> Enum.reject(&is_nil/1)
      :ets.insert(@table, {key, candidates, now()})
      {:ok, candidates}
    else
      {:hit, candidates} -> {:ok, candidates}
      {:ok, resp} -> {:error, {:http, resp.status}}
      {:error, reason} -> {:error, reason}
    end
  end

  def details("osm:" <> osm_id) do
    with true <- enabled?() || {:error, :disabled},
         {:ok, %{status: 200, body: [record | _]}} <-
           get(config()[:nominatim_url] || "https://nominatim.openstreetmap.org", "/lookup",
             osm_ids: osm_id,
             format: "jsonv2",
             namedetails: 1,
             extratags: 1,
             addressdetails: 1
           ) do
      names = record["namedetails"] || %{}

      {:ok,
       %{
         names:
           Map.new(@langs, &{&1, names["name:#{&1}"]})
           |> Enum.reject(fn {_, v} -> is_nil(v) end)
           |> Map.new(),
         population: parse_int(get_in(record, ["extratags", "population"])),
         record: record
       }}
    else
      {:ok, resp} -> {:error, {:http, resp.status}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp photon_lang(lang) when lang in ~w(en de fr), do: lang
  defp photon_lang(_), do: "default"

  defp candidate(%{"properties" => p, "geometry" => %{"coordinates" => [lng, lat]}} = feature) do
    with true <- p["osm_key"] == "place" and p["osm_value"] in ~w(city town village),
         type when is_binary(type) <- p["osm_type"],
         id when not is_nil(id) <- p["osm_id"],
         name when is_binary(name) <- p["name"] do
      %{
        id: "osm:#{type}#{id}",
        name: name,
        country_code: p["countrycode"] && String.upcase(p["countrycode"]),
        admin1: p["state"],
        lat: lat / 1,
        lng: lng / 1,
        feature: feature
      }
    else
      _ -> nil
    end
  end

  defp candidate(_), do: nil

  defp get(base, path, params) do
    [
      url: base <> path,
      params: params,
      headers: [{"user-agent", user_agent()}],
      retry: false,
      receive_timeout: 4_000,
      connect_options: [timeout: 2_000]
    ]
    |> Keyword.merge(config()[:req_options] || [])
    |> Req.get()
  rescue
    e -> {:error, e}
  end

  defp user_agent do
    case config()[:contact] do
      c when c in [nil, ""] -> "BASA/#{Application.spec(:basa, :vsn)}"
      c -> "BASA/#{Application.spec(:basa, :vsn)} (#{c})"
    end
  end

  defp cached(key) do
    case :ets.lookup(@table, key) do
      [{^key, value, at}] -> if now() - at < @ttl, do: {:hit, value}, else: :miss
      _ -> :miss
    end
  rescue
    ArgumentError -> :miss
  end

  defp now, do: System.monotonic_time(:millisecond)

  defp parse_int(nil), do: nil
  defp parse_int(n) when is_integer(n), do: n

  defp parse_int(text) do
    case Integer.parse(String.replace(to_string(text), ~r/[\s,.]/, "")) do
      {n, _} -> n
      :error -> nil
    end
  end

  defp config, do: Application.get_env(:basa, __MODULE__, [])
end
