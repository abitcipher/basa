defmodule Basa.Geo.Demand do
  use Ash.Resource,
    otp_app: :basa,
    domain: Basa.Geo,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "geo_demand"
    repo Basa.Repo
  end

  actions do
    defaults [:read]

    create :record do
      accept [:id, :label, :country_code, :query, :candidate]
      upsert? true
      upsert_fields [:label, :country_code, :query, :candidate, :last_searched_at]
      change set_attribute(:last_searched_at, &DateTime.utc_now/0)
      change atomic_update(:count, expr(count + 1))
    end

    create :restore do
      accept [:id, :label, :country_code, :query, :candidate, :count, :status, :last_searched_at]
      upsert? true

      upsert_fields [
        :label,
        :country_code,
        :query,
        :candidate,
        :count,
        :status,
        :last_searched_at
      ]
    end

    update :resolve do
      accept [:status]
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if actor_attribute_equals(:role, :admin)
    end

    policy action(:resolve) do
      authorize_if actor_attribute_equals(:role, :admin)
    end

    policy action([:record, :restore]) do
      forbid_if always()
    end
  end

  attributes do
    attribute :id, :string, primary_key?: true, allow_nil?: false, public?: true
    attribute :label, :string, allow_nil?: false, public?: true
    attribute :country_code, :string, public?: true
    attribute :query, :string, public?: true
    attribute :candidate, :map, public?: true
    attribute :count, :integer, default: 1, allow_nil?: false, public?: true

    attribute :status, :atom do
      constraints one_of: [:open, :added, :ignored]
      default :open
      allow_nil? false
      public? true
    end

    attribute :last_searched_at, :utc_datetime_usec, public?: true
    timestamps()
  end
end
