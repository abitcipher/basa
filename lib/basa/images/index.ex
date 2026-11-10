defmodule Basa.Images.Index do
  alias Basa.Search

  def index_name, do: Application.get_env(:basa, Basa.Search, [])[:images_index] || "stock_images"

  def image_ids(q, limit) do
    body = %{q: q, limit: limit, attributesToRetrieve: ["id"], matchingStrategy: "last"}

    case Search.enabled?() && Search.request(:post, "/indexes/#{index_name()}/search", body) do
      {:ok, %{status: 200, body: %{"hits" => hits}}} -> Enum.map(hits, & &1["id"])
      _ -> :unavailable
    end
  end

  def setup do
    if Search.enabled?() do
      Search.request(:post, "/indexes", %{uid: index_name(), primaryKey: "id"})

      Search.request(:patch, "/indexes/#{index_name()}/settings", %{
        searchableAttributes: ["queries", "title", "tags"],
        sortableAttributes: ["uses"],
        rankingRules: ["words", "typo", "proximity", "attribute", "exactness", "uses:desc"],
        typoTolerance: %{minWordSizeForTypos: %{oneTypo: 4, twoTypos: 8}}
      })

      :ok
    end
  end

  def put([]), do: :ok

  def put(images) do
    case Search.request(
           :post,
           "/indexes/#{index_name()}/documents?primaryKey=id",
           Enum.map(images, &document/1)
         ) do
      {:ok, %{status: s}} when s in 200..299 -> :ok
      {:ok, resp} -> {:error, {:http, resp.status}}
      {:error, reason} -> {:error, reason}
    end
  end

  def delete(id), do: Search.request(:delete, "/indexes/#{index_name()}/documents/#{id}", nil)

  def reindex_all do
    images = Ash.read!(Basa.Images.StockImage, authorize?: false)

    if Search.enabled?() do
      setup()
      Search.request(:delete, "/indexes/#{index_name()}/documents", nil)
      images |> Enum.chunk_every(1000) |> Enum.each(&(:ok = put(&1)))
    end

    length(images)
  end

  def document(image) do
    %{
      id: image.id,
      title: image.title,
      tags: image.tags,
      queries: image.queries,
      uses: image.uses
    }
  end
end
