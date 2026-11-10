defmodule Basa.Catalog.OfferBasket do
  use Ash.Resource,
    otp_app: :basa,
    domain: Basa.Catalog,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "offer_baskets"
    repo Basa.Repo

    references do
      reference :owner, on_delete: :delete
    end
  end

  actions do
    defaults [:read, :destroy]

    read :mine do
      filter expr(owner_id == ^actor(:id))
      prepare build(sort: [updated_at: :desc], load: [:items, :attendants])
    end

    create :create do
      primary? true
      accept [:title, :description, :service_type]
      argument :item_ids, {:array, :uuid}, default: []
      argument :attendant_ids, {:array, :uuid}, default: []
      change relate_actor(:owner)
      change manage_relationship(:item_ids, :items, type: :append_and_remove)
      change manage_relationship(:attendant_ids, :attendants, type: :append_and_remove)
    end

    update :update do
      primary? true
      require_atomic? false
      accept [:title, :description, :service_type]
      argument :item_ids, {:array, :uuid}
      argument :attendant_ids, {:array, :uuid}
      change manage_relationship(:item_ids, :items, type: :append_and_remove)
      change manage_relationship(:attendant_ids, :attendants, type: :append_and_remove)
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if relates_to_actor_via(:owner)
      authorize_if expr(exists(lots, state == :published))
    end

    policy action_type(:create) do
      authorize_if actor_present()
    end

    policy action_type([:update, :destroy]) do
      authorize_if relates_to_actor_via(:owner)
    end
  end

  changes do
    change {Basa.Search.Changes.Reindex, lots: :by_basket}, on: [:update]
  end

  attributes do
    uuid_primary_key :id

    attribute :title, :string do
      allow_nil? false
      public? true
      constraints max_length: 200
    end

    attribute :description, :string, public?: true

    attribute :service_type, :atom do
      constraints one_of: [:venue_rental, :equipment_rental, :person_time, :mixed]
      default :equipment_rental
      allow_nil? false
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :owner, Basa.Accounts.User, allow_nil?: false

    many_to_many :items, Basa.Catalog.Item do
      public? true
      through Basa.Catalog.BasketItem
      source_attribute_on_join_resource :basket_id
      destination_attribute_on_join_resource :item_id
    end

    many_to_many :attendants, Basa.Catalog.Attendant do
      public? true
      through Basa.Catalog.BasketAttendant
      source_attribute_on_join_resource :basket_id
      destination_attribute_on_join_resource :attendant_id
    end

    has_many :lots, Basa.Catalog.Lot, destination_attribute: :basket_id
  end

  aggregates do
    count :item_count, :items, public?: true
    sum :total_value, :items, :estimated_value, public?: true
  end
end
