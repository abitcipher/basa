defmodule Basa.Catalog.Item do
  use Ash.Resource,
    otp_app: :basa,
    domain: Basa.Catalog,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshTypescript.Resource, AshJsonApi.Resource]

  @writable_fields [
    :title,
    :description,
    :brand,
    :model,
    :condition,
    :estimated_value,
    :currency,
    :attrs,
    :photos,
    :no_photos,
    :ai_suggestion,
    :category_id,
    :catalog_model_id
  ]

  json_api do
    type "item"
  end

  require Ash.Query

  postgres do
    table "items"
    repo Basa.Repo

    references do
      reference :owner, on_delete: :delete
      reference :category, on_delete: :nilify
      reference :catalog_model, on_delete: :nilify
    end
  end

  typescript do
    type_name("Item")
  end

  @api_fields @writable_fields -- [:photos, :ai_suggestion, :catalog_model_id]

  actions do
    defaults [:read, :destroy]

    read :mine do
      prepare fn query, context ->
        case context.actor do
          %{id: id} -> Ash.Query.filter(query, owner_id == ^id)
          _ -> query
        end
      end

      prepare build(sort: [inserted_at: :desc], load: [:category])
    end

    create :create do
      primary? true
      accept @writable_fields
      change relate_actor(:owner)
      change Basa.Catalog.Changes.ValidateAttrs
    end

    create :api_create do
      accept @api_fields
      argument :photo_urls, {:array, :string}, constraints: [max_length: 20]
      change relate_actor(:owner)
      change Basa.Catalog.Changes.ValidateAttrs
      change Basa.Catalog.Changes.FetchPhotos
    end

    update :api_update do
      require_atomic? false
      accept @api_fields
      argument :photo_urls, {:array, :string}, constraints: [max_length: 20]
      change Basa.Catalog.Changes.ValidateAttrs
      change Basa.Catalog.Changes.FetchPhotos
    end

    update :update do
      primary? true
      require_atomic? false
      accept @writable_fields
      change Basa.Catalog.Changes.ValidateAttrs
    end

    update :mark_sold do
      accept [:sold_at]
      require_atomic? false
    end
  end

  policies do
    policy action(:mine) do
      forbid_unless actor_present()
      authorize_if always()
    end

    policy action_type(:read) do
      authorize_if relates_to_actor_via(:owner)
      authorize_if expr(exists(baskets.lots, state == :published))
    end

    policy action_type(:create) do
      authorize_if actor_present()
    end

    policy action_type([:update, :destroy]) do
      authorize_if relates_to_actor_via(:owner)
    end

    policy action(:mark_sold) do
      forbid_if always()
    end
  end

  changes do
    change {Basa.Search.Changes.Reindex, lots: :by_item}, on: [:update, :destroy]
  end

  attributes do
    uuid_primary_key :id

    attribute :sold_at, :utc_datetime_usec, public?: true

    attribute :title, :string do
      allow_nil? false
      public? true
      constraints max_length: 200
    end

    attribute :description, :string, public?: true
    attribute :brand, :string, public?: true
    attribute :model, :string, public?: true

    attribute :condition, :atom do
      constraints one_of: [:new, :excellent, :good, :fair, :worn]
      default :good
      public? true
    end

    attribute :estimated_value, :decimal, public?: true

    attribute :currency, :atom do
      constraints one_of: Basa.Money.currencies()
      default :UAH
      public? true
    end

    attribute :attrs, :map, default: %{}, public?: true

    attribute :photos, {:array, :string}, default: [], public?: true

    attribute :no_photos, :boolean, default: false, allow_nil?: false, public?: true

    attribute :ai_suggestion, :map, public?: true

    timestamps()
  end

  relationships do
    belongs_to :owner, Basa.Accounts.User, allow_nil?: false
    belongs_to :category, Basa.Catalog.Category, public?: true
    belongs_to :catalog_model, Basa.Catalog.CatalogModel, public?: true

    many_to_many :baskets, Basa.Catalog.OfferBasket do
      through Basa.Catalog.BasketItem
      source_attribute_on_join_resource :item_id
      destination_attribute_on_join_resource :basket_id
    end
  end

  calculations do
    calculate :photo_urls, {:array, :string}, fn records, _ ->
      Enum.map(records, fn r -> Enum.map(r.photos || [], &Basa.Storage.url/1) end)
    end do
      public? true
    end
  end
end
