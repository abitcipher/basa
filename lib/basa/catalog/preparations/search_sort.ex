defmodule Basa.Catalog.Preparations.SearchSort do
  use Ash.Resource.Preparation

  @impl true
  def prepare(query, _opts, _context) do
    sort =
      case Ash.Query.get_argument(query, :sort) do
        :price_asc -> [price_amount: :asc, published_at: :desc]
        :price_desc -> [price_amount: :desc, published_at: :desc]
        :newest -> [published_at: :desc]
        _ -> [featured: :desc, published_at: :desc]
      end

    Ash.Query.sort(query, sort)
  end
end
