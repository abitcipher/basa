defmodule Basa.StreetView do
  alias Basa.Images.Fetch

  require Logger

  @base "https://graph.mapillary.com"
  @api @base <> "/images"
  @fields "id,captured_at,creator,computed_geometry,geometry"
  @thumbs "thumb_256_url,thumb_1024_url"
  @radii [0.0006, 0.0015]
  @max 6

  @type view :: %{
          id: String.t(),
          preview: String.t(),
          image_url: String.t(),
          creator: String.t() | nil,
          captured_at: Date.t() | nil,
          meters: non_neg_integer()
        }

  def configured?, do: token() not in [nil, ""]

  def enabled?, do: Basa.Services.on?(:street_view)

  @spec nearby(number(), number()) :: {:ok, [view()]} | {:error, term()}
  def nearby(lat, lng) do
    if enabled?(), do: search(lat, lng, @radii), else: {:error, :off}
  end

  defp search(_lat, _lng, []), do: {:ok, []}

  defp search(lat, lng, [r | wider]) do
    with {:ok, images} <- images(lat, lng, r) do
      case nearest(images, lat, lng) do
        [] -> search(lat, lng, wider)
        views -> {:ok, Enum.flat_map(views, &(&1 |> with_thumbs() |> with_preview()))}
      end
    end
  end

  defp images(lat, lng, r) do
    params = [
      access_token: token(),
      fields: @fields,
      bbox: Enum.join([lng - r, lat - r, lng + r, lat + r], ","),
      limit: 20
    ]

    case Req.get(
           Keyword.merge(
             [
               url: @api,
               params: params,
               retry: :transient,
               max_retries: 2,
               retry_delay: fn n -> 300 * (n + 1) end,
               receive_timeout: 10_000
             ],
             req_options()
           )
         ) do
      {:ok, %{status: 200, body: %{"data" => data}}} when is_list(data) ->
        {:ok, data}

      {:ok, %{status: status, body: body}} ->
        Logger.warning(
          "Mapillary search: HTTP #{status} #{inspect(body) |> String.slice(0, 300)}"
        )

        {:error, {:http, status}}

      {:error, error} ->
        Logger.warning("Mapillary search failed: #{Exception.message(error)}")
        {:error, error}
    end
  end

  defp nearest(images, lat, lng) do
    images
    |> Enum.flat_map(fn img ->
      case point(img) do
        {ilng, ilat} ->
          [
            %{
              id: to_string(img["id"]),
              creator: get_in(img, ["creator", "username"]),
              captured_at: captured(img["captured_at"]),
              meters: meters(lat, lng, ilat, ilng)
            }
          ]

        nil ->
          []
      end
    end)
    |> Enum.sort_by(& &1.meters)
    |> Enum.take(@max)
  end

  defp point(%{"computed_geometry" => %{"coordinates" => [lng, lat]}}), do: {lng, lat}
  defp point(%{"geometry" => %{"coordinates" => [lng, lat]}}), do: {lng, lat}
  defp point(_), do: nil

  defp captured(ms) when is_integer(ms),
    do: ms |> DateTime.from_unix!(:millisecond) |> DateTime.to_date()

  defp captured(_), do: nil

  defp meters(lat1, lng1, lat2, lng2) do
    x = (lng2 - lng1) * :math.cos((lat1 + lat2) / 2 * :math.pi() / 180)
    y = lat2 - lat1
    round(:math.sqrt(x * x + y * y) * 111_320)
  end

  defp with_thumbs(view) do
    params = [access_token: token(), fields: @thumbs]

    case Req.get(
           Keyword.merge(
             [url: "#{@base}/#{view.id}", params: params, retry: false, receive_timeout: 10_000],
             req_options()
           )
         ) do
      {:ok, %{status: 200, body: %{"thumb_256_url" => small, "thumb_1024_url" => large}}}
      when is_binary(small) and is_binary(large) ->
        Map.merge(view, %{thumb: small, image_url: large})

      _ ->
        nil
    end
  end

  defp with_preview(nil), do: []

  defp with_preview(view) do
    case Fetch.image(view.thumb) do
      {:ok, bytes, type} ->
        [
          view
          |> Map.delete(:thumb)
          |> Map.put(:preview, "data:#{type};base64," <> Base.encode64(bytes))
        ]

      {:error, _} ->
        []
    end
  end

  @spec keep(view() | map(), String.t()) :: {:ok, map()} | {:error, term()}
  def keep(view, owner_id) do
    with {:ok, bytes, type} <- Fetch.image(view.image_url),
         {:ok, key} <- Basa.Storage.store("street/#{owner_id}", bytes, type) do
      {:ok,
       %{
         "key" => key,
         "id" => view.id,
         "creator" => view.creator,
         "captured_at" => view.captured_at && Date.to_iso8601(view.captured_at)
       }}
    end
  end

  def link(%{"id" => id}), do: "https://www.mapillary.com/app/?pKey=#{id}"

  def valid?(nil, _owner_id), do: true

  def valid?(%{"key" => key, "id" => id}, owner_id) when is_binary(key) and is_binary(id),
    do: String.starts_with?(key, "street/#{owner_id}/") and id =~ ~r/^\d+$/

  def valid?(_, _), do: false

  defp token, do: config()[:token]
  defp req_options, do: config()[:req_options] || []
  defp config, do: Application.get_env(:basa, __MODULE__, [])
end
