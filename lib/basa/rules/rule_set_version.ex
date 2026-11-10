defmodule Basa.Rules.RuleSetVersion do
  use Ash.Resource,
    otp_app: :basa,
    domain: Basa.Rules,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "rule_set_versions"
    repo Basa.Repo

    custom_indexes do
      index [:key, :version], unique: true
    end
  end

  actions do
    defaults [:read, create: :*]
  end

  policies do
    policy action_type(:read) do
      authorize_if actor_attribute_equals(:role, :admin)
    end

    policy action_type([:create, :update, :destroy]) do
      forbid_if always()
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :key, :string, allow_nil?: false, public?: true
    attribute :version, :integer, allow_nil?: false, public?: true
    attribute :graph, :map, allow_nil?: false, public?: true
    attribute :replaced_by_email, :string, public?: true
    create_timestamp :inserted_at
  end
end
