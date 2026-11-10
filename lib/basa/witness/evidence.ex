defmodule Basa.Witness.Evidence do
  use Ash.Resource,
    otp_app: :basa,
    domain: Basa.Witness,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "witness_evidence"
    repo Basa.Repo

    references do
      reference :transaction, on_delete: :delete
    end
  end

  actions do
    defaults [:read]

    create :record do
      accept [
        :position,
        :kind,
        :media_type,
        :size,
        :sha256,
        :stored_sha256,
        :storage_key,
        :added_by_id,
        :act_id
      ]

      argument :transaction_id, :uuid, allow_nil?: false
      change set_attribute(:transaction_id, arg(:transaction_id))
    end
  end

  policies do
    bypass actor_attribute_equals(:role, :admin) do
      authorize_if always()
    end

    policy action_type(:read) do
      authorize_if expr(exists(transaction.parties, user_id == ^actor(:id)))
    end

    policy action_type([:create, :update, :destroy]) do
      forbid_if always()
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :position, :integer, allow_nil?: false, public?: true

    attribute :kind, :atom do
      constraints one_of: [:contract, :photo, :voice, :other]
      allow_nil? false
      public? true
    end

    attribute :media_type, :string, allow_nil?: false, public?: true
    attribute :size, :integer, allow_nil?: false, public?: true
    attribute :sha256, :binary, allow_nil?: false, public?: true
    attribute :storage_key, :string, allow_nil?: false

    attribute :stored_sha256, :binary

    timestamps()
  end

  relationships do
    belongs_to :transaction, Basa.Witness.Transaction, allow_nil?: false
    belongs_to :added_by, Basa.Accounts.User, public?: true

    belongs_to :act, Basa.Witness.Act, public?: true
  end

  identities do
    identity :unique_position, [:transaction_id, :act_id, :position], nils_distinct?: false
    identity :unique_file, [:transaction_id, :act_id, :sha256], nils_distinct?: false
  end
end
