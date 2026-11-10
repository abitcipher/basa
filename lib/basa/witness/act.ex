defmodule Basa.Witness.Act do
  use Ash.Resource,
    otp_app: :basa,
    domain: Basa.Witness,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "witness_acts"
    repo Basa.Repo

    references do
      reference :transaction, on_delete: :delete
    end
  end

  actions do
    defaults [:read]

    create :start do
      description "A party starts an act it may make now (Acts.Start checks the rules)."
      accept [:kind, :terms]
      argument :transaction_id, :uuid, allow_nil?: false
      change set_attribute(:transaction_id, arg(:transaction_id))
      change Basa.Witness.Acts.Start
    end

    update :edit do
      accept [:terms]
      validate attribute_equals(:status, :draft)
    end

    update :fix do
      description "Fixes the act: canonical bytes, ACT-HASH, its place in the chain."
      require_atomic? false
      validate attribute_equals(:status, :draft)
      change Basa.Witness.Acts.Fix
    end

    update :sign do
      require_atomic? false
      argument :signature, :binary, allow_nil?: false
      validate attribute_equals(:status, :unsigned)
      change Basa.Witness.Acts.Sign
    end

    update :countersign do
      description "The other party agrees to a settlement."
      require_atomic? false
      argument :signature, :binary, allow_nil?: false
      validate attribute_equals(:status, :awaiting_counter)
      change Basa.Witness.Acts.Countersign
    end

    update :reject do
      description "The other party does not agree to a settlement."
      validate attribute_equals(:status, :awaiting_counter)
      change set_attribute(:status, :rejected)
    end

    update :set_recovery do
      accept [:recovery_sealed]
    end

    create :auto_accept do
      argument :transaction_id, :uuid, allow_nil?: false
      change set_attribute(:transaction_id, arg(:transaction_id))
      change Basa.Witness.Acts.AutoAccept
    end
  end

  policies do
    policy action(:start) do
      authorize_if Basa.Witness.Checks.TransactionParty
    end

    policy action([:edit, :fix, :sign]) do
      authorize_if expr(author_user_id == ^actor(:id))
    end

    policy action([:countersign, :reject]) do
      authorize_if expr(
                     author_user_id != ^actor(:id) and
                       exists(transaction.parties, user_id == ^actor(:id))
                   )
    end

    policy action([:auto_accept, :set_recovery]) do
      forbid_if always()
    end

    policy action_type(:read) do
      authorize_if expr(exists(transaction.parties, user_id == ^actor(:id)))
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :kind, :atom do
      constraints one_of: [
                    :return,
                    :delivery,
                    :acceptance,
                    :claim,
                    :settlement,
                    :dispute,
                    :auto_acceptance
                  ]

      allow_nil? false
      public? true
    end

    attribute :author, :atom do
      constraints one_of: [:offeror, :acceptor, :basa]
      allow_nil? false
      public? true
    end

    attribute :author_user_id, :uuid, public?: true

    attribute :status, :atom do
      constraints one_of: [:draft, :unsigned, :awaiting_counter, :effective, :rejected]
      default :draft
      allow_nil? false
      public? true
    end

    attribute :terms, :map, default: %{}, allow_nil?: false, public?: true

    attribute :sequence, :integer, public?: true
    attribute :bytes, :binary
    attribute :hash, :binary, public?: true
    attribute :previous, :binary, public?: true

    attribute :recovery_sealed, :binary, sensitive?: true

    attribute :author_signature, :binary, public?: true
    attribute :counter_signature, :binary, public?: true
    attribute :effective_at, :utc_datetime_usec, public?: true

    timestamps()
  end

  relationships do
    belongs_to :transaction, Basa.Witness.Transaction, allow_nil?: false, public?: true
    has_many :evidence, Basa.Witness.Evidence, sort: [position: :asc], public?: true
  end

  identities do
    identity :one_place_in_chain, [:transaction_id, :sequence], nils_distinct?: true
  end
end
