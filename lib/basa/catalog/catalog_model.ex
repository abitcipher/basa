defmodule Basa.Catalog.CatalogModel do
  use Ash.Resource,
    otp_app: :basa,
    domain: Basa.Catalog,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "catalog_models"
    repo Basa.Repo

    references do
      reference :category, on_delete: :nilify
    end
  end

  actions do
    defaults [:read]

    create :create do
      primary? true

      accept [
        :brand,
        :model,
        :category_id,
        :reference_url,
        :market_price,
        :market_price_currency,
        :market_price_source
      ]

      change set_attribute(:market_price_at, &DateTime.utc_now/0)
    end

    read :lookup do
      argument :brand, :string, allow_nil?: false
      argument :model, :string, allow_nil?: false
      get? true
      filter expr(fragment("lower(?)", brand) == fragment("lower(?)", ^arg(:brand)))
      filter expr(fragment("lower(?)", model) == fragment("lower(?)", ^arg(:model)))
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if always()
    end

    policy action_type(:create) do
      authorize_if actor_present()
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :brand, :string, allow_nil?: false, public?: true
    attribute :model, :string, allow_nil?: false, public?: true
    attribute :reference_url, :string, public?: true
    attribute :market_price, :decimal, public?: true

    attribute :market_price_currency, :atom do
      constraints one_of: Basa.Money.currencies()
      public? true
    end

    attribute :market_price_source, :string, public?: true
    attribute :market_price_at, :utc_datetime_usec, public?: true
    timestamps()
  end

  relationships do
    belongs_to :category, Basa.Catalog.Category, public?: true
  end

  identities do
    identity :unique_brand_model, [:brand, :model]
  end
end
