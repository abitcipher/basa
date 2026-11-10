defmodule Basa.Rules.RuleSet do
  use Ash.Resource,
    otp_app: :basa,
    domain: Basa.Rules,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "rule_sets"
    repo Basa.Repo
  end

  actions do
    defaults [:read]

    create :seed do
      accept [:key, :label, :description, :severity, :points, :subjects, :graph, :version]
    end

    update :ship do
      accept [:label, :description, :points, :subjects, :graph, :version]
    end

    update :configure do
      require_atomic? false
      accept [:severity, :enabled]
      change Basa.Rules.Changes.Stamp
    end

    update :update_graph do
      require_atomic? false
      accept [:graph]
      change Basa.Rules.Changes.ValidateGraph
      change Basa.Rules.Changes.KeepVersion
      change Basa.Rules.Changes.Stamp
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if actor_attribute_equals(:role, :admin)
    end

    policy action([:seed, :ship]) do
      forbid_if always()
    end

    policy action_type([:create, :update, :destroy]) do
      authorize_if actor_attribute_equals(:role, :admin)
    end
  end

  attributes do
    attribute :key, :string, primary_key?: true, allow_nil?: false, public?: true
    attribute :label, :string, allow_nil?: false, public?: true
    attribute :description, :string, public?: true

    attribute :severity, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:block, :flag, :observe]
      default :flag
    end

    attribute :points, {:array, :string}, allow_nil?: false, default: [], public?: true
    attribute :subjects, {:array, :string}, allow_nil?: false, default: [], public?: true
    attribute :enabled, :boolean, allow_nil?: false, default: true, public?: true
    attribute :graph, :map, allow_nil?: false, public?: true
    attribute :version, :integer, allow_nil?: false, default: 1, public?: true
    attribute :updated_by_email, :string, public?: true
    timestamps()
  end
end
