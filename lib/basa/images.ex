defmodule Basa.Images do
  use Ash.Domain, otp_app: :basa

  require Ash.Query
  require Logger
  alias Basa.Images.{Fetch, Index, Openverse, StockImage}

  resources do
    resource StockImage
  end

  def configured?, do: Keyword.get(config(), :enabled, true)

  def enabled?, do: configured?() and Basa.Services.on?(:images)

  @spec suggest(map(), keyword()) :: [Basa.Images.Source.candidate()]
  def suggest(listing, opts \\ []) do
    limit = opts[:limit] || 8
    kept = kept(listing_text(listing), limit)

    found =
      if enabled?() and length(kept) < limit,
        do: found(listing, limit, MapSet.new(kept, & &1.source_id)),
        else: []

    Enum.take(kept ++ found, limit)
  end

  @spec attach(Basa.Images.Source.candidate(), map()) :: {:ok, String.t()} | {:error, term()}
  def attach(candidate, listing \\ %{}) do
    query = listing_text(listing)

    case existing(candidate) do
      %StockImage{} = image ->
        used(image, query)

      nil ->
        with {:ok, body, type} <- Fetch.image(candidate.url) do
          sha = :crypto.hash(:sha256, body) |> Base.encode16(case: :lower)

          case Ash.get(StockImage, %{key: key(sha, type)}, authorize?: false) do
            {:ok, image} -> used(image, query)
            {:error, _} -> keep(candidate, body, type, sha, query)
          end
        end
    end
  end

  def credits(keys) do
    stock = Enum.filter(keys || [], &stock?/1)

    if stock == [] do
      %{}
    else
      StockImage
      |> Ash.Query.filter(key in ^stock)
      |> Ash.read!(authorize?: false)
      |> Map.new(&{&1.key, &1})
    end
  end

  def stock?("stock/" <> _), do: true
  def stock?(_), do: false

  def user_agent do
    case config()[:contact] do
      c when c in [nil, ""] -> "BASA/#{Application.spec(:basa, :vsn)}"
      c -> "BASA/#{Application.spec(:basa, :vsn)} (#{c})"
    end
  end

  @doc false
  def req_options, do: config()[:req_options] || []

  @doc false
  def check_hosts?, do: Keyword.get(config(), :check_hosts, true)

  defp listing_text(listing) do
    [
      join([listing[:brand], listing[:model]]),
      listing[:title],
      category_name(listing[:category])
    ]
    |> Enum.map(&clean/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq_by(&String.downcase/1)
    |> Enum.join(" ")
  end

  defp outside_queries(listing) do
    category = category_name(listing[:category])
    title = clean(listing[:title])

    words = String.split(title)

    ([
       join([listing[:brand], listing[:model]]),
       title,
       join([listing[:brand], category]),
       category
     ] ++
       for(n <- (length(words) - 1)..1//-1, do: words |> Enum.take(n) |> Enum.join(" ")) ++
       [
         listing[:brand],
         listing[:description] |> clean() |> String.split() |> Enum.take(6) |> Enum.join(" ")
       ])
    |> Enum.map(&clean/1)
    |> Enum.filter(&latin?/1)
    |> Enum.uniq_by(&String.downcase/1)
    |> Enum.take(3)
  end

  defp kept("", _limit), do: []

  defp kept(text, limit) do
    ids =
      case Index.image_ids(text, limit) do
        :unavailable -> nil
        ids -> ids
      end

    images =
      if ids do
        rank = ids |> Enum.with_index() |> Map.new()

        StockImage
        |> Ash.Query.filter(id in ^ids)
        |> Ash.read!(authorize?: false)
        |> Enum.sort_by(&rank[&1.id])
      else
        postgres_kept(text, limit)
      end

    Enum.map(images, &kept_candidate/1)
  end

  defp postgres_kept(text, limit) do
    words =
      text
      |> String.split()
      |> Enum.filter(&(String.length(&1) >= 3))
      |> Enum.take(6)
      |> Enum.map(&"%#{String.replace(&1, ~r/[%_\\]/, "")}%")

    if words == [] do
      []
    else
      StockImage
      |> Ash.Query.filter(
        fragment(
          "(coalesce(?, '') || ' ' || array_to_string(?, ' ')) ILIKE ANY(?)",
          title,
          queries,
          ^words
        )
      )
      |> Ash.Query.sort(uses: :desc)
      |> Ash.Query.limit(limit)
      |> Ash.read!(authorize?: false)
    end
  end

  defp found(listing, limit, seen) do
    listing
    |> outside_queries()
    |> Enum.reduce_while([], fn query, acc ->
      case Openverse.search(query, limit) do
        {:ok, candidates} ->
          acc = Enum.uniq_by(acc ++ candidates, & &1.source_id)
          if length(acc) >= limit, do: {:halt, acc}, else: {:cont, acc}

        {:error, reason} ->
          Logger.info("openverse: #{inspect(reason)}")
          {:halt, acc}
      end
    end)
    |> Enum.reject(&MapSet.member?(seen, &1.source_id))
  end

  defp kept_candidate(image) do
    %{
      ref: "stock:" <> image.id,
      source: image.source,
      source_id: image.source_id,
      key: image.key,
      url: nil,
      thumbnail: Basa.Storage.url(image.key),
      title: image.title,
      creator: image.creator,
      creator_url: image.creator_url,
      license: image.license,
      license_version: image.license_version,
      license_url: image.license_url,
      landing_url: image.landing_url,
      width: image.width,
      height: image.height,
      tags: image.tags
    }
  end

  defp existing(%{key: key}) when is_binary(key) do
    case Ash.get(StockImage, %{key: key}, authorize?: false) do
      {:ok, image} -> image
      _ -> nil
    end
  end

  defp existing(%{source: source, source_id: id}) do
    StockImage
    |> Ash.Query.filter(source == ^source and source_id == ^id)
    |> Ash.read_one!(authorize?: false)
  end

  defp keep(c, body, type, sha, query) do
    key = key(sha, type)

    with :ok <- Basa.Storage.put(key, body, type),
         :ok <- Basa.Moderation.queue(key),
         {:ok, image} <-
           StockImage
           |> Ash.Changeset.for_create(
             :cache,
             %{
               key: key,
               sha256: sha,
               content_type: type,
               byte_size: byte_size(body),
               width: c.width,
               height: c.height,
               source: c.source,
               source_id: c.source_id,
               title: c.title,
               creator: c.creator,
               creator_url: c.creator_url,
               license: c.license,
               license_version: c.license_version,
               license_url: c.license_url,
               landing_url: c.landing_url,
               original_url: c.url,
               tags: c.tags,
               queries: if(query == "", do: [], else: [query])
             },
             authorize?: false
           )
           |> Ash.create(authorize?: false) do
      {:ok, image.key}
    end
  end

  defp used(image, query) do
    with {:ok, image} <-
           image
           |> Ash.Changeset.for_update(:used, %{query: query}, authorize?: false)
           |> Ash.update(authorize?: false),
         do: {:ok, image.key}
  end

  defp key(sha, "image/jpeg"), do: "stock/#{sha}.jpg"
  defp key(sha, "image/png"), do: "stock/#{sha}.png"
  defp key(sha, "image/webp"), do: "stock/#{sha}.webp"

  defp category_name(%{name: name}) when is_map(name), do: name["en"]
  defp category_name(_), do: nil

  defp join(parts), do: parts |> Enum.reject(&(&1 in [nil, ""])) |> Enum.join(" ")

  defp clean(nil), do: ""
  defp clean(text), do: text |> to_string() |> String.replace(~r/\s+/u, " ") |> String.trim()

  defp latin?(""), do: false

  defp latin?(text) do
    letters = Regex.scan(~r/\p{L}/u, text) |> length()
    latin = Regex.scan(~r/\p{Latin}/u, text) |> length()
    letters > 0 and latin / letters >= 0.6
  end

  defp config, do: Application.get_env(:basa, __MODULE__, [])
end
