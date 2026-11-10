defmodule Basa.Search do
  require Logger
  require Ash.Query

  def index_name, do: config()[:index] || "lots"
  def enabled?, do: config()[:url] not in [nil, ""]

  def lot_ids(q, opts \\ []) when is_binary(q) do
    filters =
      [
        opts[:city] && "city = #{quote_value(opts[:city])}",
        opts[:city_id] && "city_id = #{quote_value(opts[:city_id])}",
        opts[:service_type] && "service_type = #{quote_value(to_string(opts[:service_type]))}"
      ]
      |> Enum.reject(&is_nil/1)

    body = %{q: q, limit: opts[:limit] || 100, attributesToRetrieve: ["id"], filter: filters}

    with true <- enabled?(),
         {:ok, %{status: 200, body: %{"hits" => hits}}} <-
           request(:post, "/indexes/#{index_name()}/search", body) do
      Enum.map(hits, & &1["id"])
    else
      other ->
        Logger.debug("meilisearch unavailable: #{inspect(other)}")
        :unavailable
    end
  end

  def find_lots(args, opts \\ []) do
    actor = Keyword.get(opts, :actor)
    limit = Keyword.get(opts, :limit, 50)
    q = args[:q]

    case q &&
           lot_ids(q,
             city: args[:city],
             city_id: args[:city_id],
             service_type: args[:service_type]
           ) do
      ids when is_list(ids) ->
        rank = ids |> Enum.with_index() |> Map.new()

        lots = args |> Map.merge(%{q: nil, ids: ids}) |> read(actor, limit)

        if args[:sort] in [nil, :recommended],
          do:
            Enum.sort_by(
              lots,
              &{if(&1.featured, do: 0, else: 1), Map.get(rank, &1.id, 1_000_000)}
            ),
          else: lots

      _ ->
        read(args, actor, limit)
    end
  end

  defp read(args, actor, limit) do
    case Basa.Catalog.search_lots!(args, actor: actor, page: [limit: limit]) do
      %{results: results} -> results
      list -> list
    end
  end

  def setup do
    with true <- enabled?() do
      request(:post, "/indexes", %{uid: index_name(), primaryKey: "id"})

      request(:patch, "/indexes/#{index_name()}/settings", %{
        searchableAttributes: [
          "title",
          "items",
          "brands",
          "description",
          "room",
          "city",
          "attendants"
        ],
        filterableAttributes: [
          "city",
          "city_id",
          "service_type",
          "deal",
          "mobile",
          "currency",
          "owner_id",
          "_geo"
        ],
        sortableAttributes: ["published_at", "price_amount"],
        typoTolerance: %{minWordSizeForTypos: %{oneTypo: 4, twoTypos: 8}},
        displayedAttributes: ["*"]
      })

      :ok
    end
  end

  def index_lot(lot_id) do
    case Ash.get(Basa.Catalog.Lot, lot_id,
           load: [:room, basket: [:items, :attendants]],
           authorize?: false
         ) do
      {:ok, %{state: :published} = lot} -> put([document(lot)])
      _ -> delete(lot_id)
    end
  end

  def reindex_all do
    setup()

    Basa.Catalog.Lot
    |> Ash.Query.filter(state == :published)
    |> Ash.Query.load([:room, basket: [:items, :attendants]])
    |> Ash.read!(authorize?: false)
    |> Enum.map(&document/1)
    |> Enum.chunk_every(500)
    |> Enum.each(&put/1)
  end

  def document(lot) do
    items = lot.basket.items

    %{
      id: lot.id,
      title: lot.title,
      description: lot.description,
      items:
        Enum.map(
          items,
          &Enum.join(Enum.reject([&1.title, &1.brand, &1.model], fn v -> v in [nil, ""] end), " ")
        ),
      brands: items |> Enum.map(& &1.brand) |> Enum.reject(&is_nil/1) |> Enum.uniq(),
      attendants: Enum.map(lot.basket.attendants, &"#{&1.name} #{&1.role}"),
      room: lot.room.title,
      city: lot.room.city,
      city_id: lot.room.city_id,
      mobile: lot.room.mobile,
      service_type: to_string(lot.basket.service_type),
      deal: to_string(lot.deal),
      price_amount: Decimal.to_float(lot.price_amount),
      currency: to_string(lot.currency),
      owner_id: lot.owner_id,
      published_at: lot.published_at && DateTime.to_unix(lot.published_at),
      _geo: %{lat: lot.room.lat, lng: lot.room.lng}
    }
  end

  def wait_idle(timeout \\ 10_000, index \\ index_name()) do
    deadline = System.monotonic_time(:millisecond) + timeout

    Stream.repeatedly(fn ->
      case request(:get, "/tasks?statuses=enqueued,processing&indexUids=#{index}", nil) do
        {:ok, %{status: 200, body: %{"total" => 0}}} -> :idle
        _ -> Process.sleep(100) && :busy
      end
    end)
    |> Enum.find(fn state -> state == :idle or System.monotonic_time(:millisecond) > deadline end)
  end

  defp put(docs), do: request(:post, "/indexes/#{index_name()}/documents?primaryKey=id", docs)
  defp delete(id), do: request(:delete, "/indexes/#{index_name()}/documents/#{id}", nil)

  def request(method, path, body) do
    if enabled?() do
      [
        method: method,
        url: config()[:url] <> path,
        auth: {:bearer, config()[:key] || ""},
        retry: false,
        receive_timeout: 5_000,
        connect_options: [timeout: 2_000]
      ]
      |> then(&if(is_nil(body), do: &1, else: Keyword.put(&1, :json, body)))
      |> Req.request()
    else
      {:error, :disabled}
    end
  rescue
    e -> {:error, e}
  end

  def quote_value(v), do: ~s("#{String.replace(to_string(v), ~s("), ~s(\\"))}")

  defp config, do: Application.get_env(:basa, __MODULE__, [])
end
