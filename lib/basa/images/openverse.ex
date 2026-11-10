defmodule Basa.Images.Openverse do
  use GenServer
  @behaviour Basa.Images.Source

  @table :basa_images_openverse
  @ttl :timer.hours(24)
  @pause :timer.minutes(10)
  @licenses "cc0,pdm,by,by-sa"

  def start_link(_), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @impl GenServer
  def init(nil) do
    :ets.new(@table, [:named_table, :public, read_concurrency: true])
    {:ok, nil}
  end

  @impl Basa.Images.Source
  def search(query, limit) do
    key = {:search, String.downcase(query), limit}

    with :miss <- cached(key),
         :ok <- not_paused(),
         {:ok, %{status: 200, body: %{"results" => results}}} <-
           get("/v1/images/",
             q: query,
             license: @licenses,
             page_size: limit,
             mature: false
           ) do
      candidates = results |> Enum.map(&candidate/1) |> Enum.reject(&is_nil/1)
      cache(key, candidates)
      {:ok, candidates}
    else
      {:hit, candidates} ->
        {:ok, candidates}

      {:ok, %{status: 429}} ->
        :ets.insert(@table, {:paused_until, now() + @pause})
        {:error, :rate_limited}

      {:ok, resp} ->
        {:error, {:http, resp.status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp candidate(%{"id" => id, "url" => url, "license" => license} = r)
       when is_binary(url) and license in ~w(cc0 pdm by by-sa) do
    %{
      ref: "openverse:" <> id,
      source: :openverse,
      source_id: id,
      key: nil,
      url: url,
      thumbnail: r["thumbnail"] || url,
      title: r["title"],
      creator: r["creator"],
      creator_url: r["creator_url"],
      license: license,
      license_version: r["license_version"],
      license_url: r["license_url"],
      landing_url: r["foreign_landing_url"],
      width: r["width"],
      height: r["height"],
      tags: r |> Map.get("tags", []) |> Enum.map(& &1["name"]) |> Enum.uniq()
    }
  end

  defp candidate(_), do: nil

  defp get(path, params) do
    [
      url: (config()[:url] || "https://api.openverse.org") <> path,
      params: params,
      headers: [{"user-agent", Basa.Images.user_agent()}],
      retry: false,
      receive_timeout: 6_000,
      connect_options: [timeout: 3_000]
    ]
    |> Keyword.merge(Basa.Images.req_options())
    |> Req.get()
  rescue
    e -> {:error, e}
  end

  defp not_paused do
    case :ets.lookup(@table, :paused_until) do
      [{_, until}] -> if now() < until, do: {:error, :rate_limited}, else: :ok
      _ -> :ok
    end
  rescue
    ArgumentError -> :ok
  end

  defp cached(key) do
    case :ets.lookup(@table, key) do
      [{^key, value, at}] -> if now() - at < ttl(), do: {:hit, value}, else: :miss
      _ -> :miss
    end
  rescue
    ArgumentError -> :miss
  end

  defp cache(key, value) do
    if ttl() > 0, do: :ets.insert(@table, {key, value, now()})
  rescue
    ArgumentError -> :ok
  end

  defp ttl, do: if(Keyword.get(config(), :cache, true), do: @ttl, else: 0)
  defp now, do: System.monotonic_time(:millisecond)
  defp config, do: Application.get_env(:basa, __MODULE__, [])
end
