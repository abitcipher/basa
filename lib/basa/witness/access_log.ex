defmodule Basa.Witness.AccessLog do
  use Ash.Resource,
    otp_app: :basa,
    domain: Basa.Witness,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "witness_access_logs"
    repo Basa.Repo

    references do
      reference :transaction, on_delete: :restrict
    end
  end

  actions do
    defaults [:read]

    create :record do
      accept [:action, :reason, :reference, :result, :actor_id]
      argument :transaction_id, :uuid, allow_nil?: false
      change set_attribute(:transaction_id, arg(:transaction_id))
    end
  end

  policies do
    bypass actor_attribute_equals(:role, :admin) do
      authorize_if action_type(:read)
    end

    policy always() do
      forbid_if always()
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :action, :atom do
      constraints one_of: [:verify, :open, :request, :recovery]
      allow_nil? false
      public? true
    end

    attribute :reason, :string, public?: true
    attribute :reference, :string, public?: true
    attribute :result, :string, allow_nil?: false, public?: true

    create_timestamp :inserted_at
  end

  relationships do
    belongs_to :transaction, Basa.Witness.Transaction, allow_nil?: false, public?: true
    belongs_to :actor, Basa.Accounts.User, public?: true
  end
end
