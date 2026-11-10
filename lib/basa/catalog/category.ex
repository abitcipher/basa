defmodule Basa.Catalog.Category do
  use Ash.Resource,
    otp_app: :basa,
    domain: Basa.Catalog,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshJsonApi.Resource]

  json_api do
    type "category"
  end

  postgres do
    table "categories"
    repo Basa.Repo
  end

  actions do
    defaults [:read]

    create :create do
      primary? true
      accept [:slug, :name, :kind, :parent_slug, :attr_schema, :position]
    end

    update :update do
      primary? true
      accept [:name, :attr_schema, :position]
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if always()
    end

    policy action_type([:create, :update]) do
      authorize_if actor_attribute_equals(:role, :admin)
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :slug, :string, allow_nil?: false, public?: true

    attribute :name, :map, allow_nil?: false, public?: true

    attribute :kind, :atom do
      constraints one_of: [:equipment, :venue, :person]
      allow_nil? false
      public? true
    end

    attribute :parent_slug, :string, public?: true
    attribute :attr_schema, :map, default: %{}, public?: true
    attribute :position, :integer, default: 0, public?: true

    timestamps()
  end

  identities do
    identity :unique_slug, [:slug]
  end

  def display_name(%__MODULE__{name: name, slug: slug}, locale) do
    name[to_string(locale)] || name["en"] || slug
  end
end
