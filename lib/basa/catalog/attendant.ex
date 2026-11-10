defmodule Basa.Catalog.Attendant do
  use Ash.Resource,
    otp_app: :basa,
    domain: Basa.Catalog,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "attendants"
    repo Basa.Repo

    references do
      reference :owner, on_delete: :delete
    end
  end

  actions do
    defaults [:read, :destroy]

    read :mine do
      filter expr(owner_id == ^actor(:id))
      prepare build(sort: [name: :asc])
    end

    create :create do
      primary? true
      accept [:name, :role, :phone, :telegram_username, :bio]
      change relate_actor(:owner)
    end

    update :update do
      primary? true
      accept [:name, :role, :phone, :telegram_username, :bio]
    end
  end

  policies do
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
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false, public?: true

    attribute :role, :atom do
      constraints one_of: [:sound_engineer, :assistant, :guide, :key_holder, :specialist, :other]
      default :assistant
      allow_nil? false
      public? true
    end

    attribute :phone, :string
    attribute :telegram_username, :string
    attribute :bio, :string, public?: true
    timestamps()
  end

  relationships do
    belongs_to :owner, Basa.Accounts.User, allow_nil?: false

    many_to_many :baskets, Basa.Catalog.OfferBasket do
      through Basa.Catalog.BasketAttendant
      source_attribute_on_join_resource :attendant_id
      destination_attribute_on_join_resource :basket_id
    end
  end
end
