defmodule Basa.Import.Entry do
  use Ash.Resource,
    otp_app: :basa,
    domain: Basa.Import,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshJsonApi.Resource]

  json_api do
    type "import_entry"
  end

  postgres do
    table "import_entries"
    repo Basa.Repo

    references do
      reference :source, on_delete: :delete
      reference :item, on_delete: :nilify
    end
  end

  actions do
    defaults [:read]

    create :record do
      accept [:url, :status, :error, :fingerprint, :item_id]
      argument :source_id, :uuid, allow_nil?: false
      upsert? true
      upsert_identity :unique_url
      upsert_fields [:status, :error, :fingerprint, :item_id, :imported_at, :updated_at]

      change set_attribute(:source_id, arg(:source_id))
      change set_attribute(:imported_at, &DateTime.utc_now/0)
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if actor_attribute_equals(:role, :admin)
      authorize_if expr(source.owner_id == ^actor(:id))
    end

    policy action(:record) do
      authorize_if Basa.Import.Checks.HasAccess
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :url, :string, allow_nil?: false, public?: true

    attribute :status, :atom,
      allow_nil?: false,
      public?: true,
      constraints: [one_of: [:created, :updated, :unchanged, :skipped, :failed]]

    attribute :error, :string, public?: true
    attribute :fingerprint, :string, public?: true
    attribute :imported_at, :utc_datetime_usec, allow_nil?: false, public?: true
    timestamps()
  end

  relationships do
    belongs_to :source, Basa.Import.Source, allow_nil?: false, public?: true
    belongs_to :item, Basa.Catalog.Item, public?: true
  end

  identities do
    identity :unique_url, [:source_id, :url]
  end
end
