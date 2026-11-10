defmodule Basa.Witness.MemAttestation do
  use Ash.Resource,
    otp_app: :basa,
    domain: Basa.Witness,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias Basa.Witness.MemAttest

  postgres do
    table "witness_mem_attestations"
    repo Basa.Repo

    references do
      reference :transaction, on_delete: :delete
    end
  end

  actions do
    defaults [:read]

    create :issue do
      argument :transaction_id, :uuid, allow_nil?: false
      change set_attribute(:transaction_id, arg(:transaction_id))
      change {MemAttest.Issue, []}
    end

    update :receive do
      require_atomic? false
      argument :attestation, :binary, allow_nil?: false, sensitive?: true

      argument :via, :atom do
        constraints one_of: [:https, :paste]
        allow_nil? false
      end

      change {MemAttest.Receive, []}
    end
  end

  policies do
    bypass actor_attribute_equals(:role, :admin) do
      authorize_if action_type(:read)
    end

    policy action(:issue) do
      authorize_if Basa.Witness.Checks.TransactionParty
    end

    policy action_type(:read) do
      authorize_if expr(exists(transaction.parties, user_id == ^actor(:id)))
    end

    policy action(:receive) do
      authorize_if relates_to_actor_via(:user)
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :role, :atom do
      constraints one_of: [:offeror, :acceptor]
      allow_nil? false
      public? true
    end

    attribute :challenge, :binary, allow_nil?: false

    attribute :status, :atom do
      constraints one_of: [:pending, :received]
      default :pending
      allow_nil? false
      public? true
    end

    attribute :attestation, :binary
    attribute :statement, :binary
    attribute :attest_key, :binary, public?: true

    attribute :via, :atom do
      constraints one_of: [:https, :paste]
      public? true
    end

    attribute :received_at, :utc_datetime_usec, public?: true
    create_timestamp :inserted_at, public?: true
  end

  relationships do
    belongs_to :transaction, Basa.Witness.Transaction, allow_nil?: false, public?: true
    belongs_to :user, Basa.Accounts.User, allow_nil?: false, public?: true
  end

  identities do
    identity :unique_challenge, [:challenge]
  end
end
