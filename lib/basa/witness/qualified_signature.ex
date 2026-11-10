defmodule Basa.Witness.QualifiedSignature do
  use Ash.Resource,
    otp_app: :basa,
    domain: Basa.Witness,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  @type t :: %__MODULE__{}

  postgres do
    table "witness_qualified_signatures"
    repo Basa.Repo

    references do
      reference :transaction, on_delete: :delete
    end
  end

  actions do
    defaults [:read]

    create :start do
      argument :transaction_id, :uuid, allow_nil?: false
      argument :provider, :atom, allow_nil?: false
      change set_attribute(:transaction_id, arg(:transaction_id))
      change set_attribute(:provider, arg(:provider))
      change {Basa.Witness.QES.Start, []}
    end

    update :complete do
      require_atomic? false
      argument :cms, :binary, allow_nil?: false, sensitive?: true
      change {Basa.Witness.QES.Complete, []}
    end

    update :advance do
      description "Keeps the provider's state between round trips (Basa.Witness.QES.Provider)."
      accept [:provider_data]
    end

    update :record_qualification do
      description "The EU DSS's answer when it came after the signing (QualifyWorker)."
      require_atomic? false

      accept [
        :qualification,
        :qualification_level,
        :qualification_indication,
        :qualification_report,
        :qualification_checked_at
      ]

      change {Basa.Witness.QES.Qualified, []}
    end

    update :fail do
      argument :reason, :string
      change set_attribute(:status, :failed)
      change set_attribute(:failure, arg(:reason))
    end
  end

  policies do
    bypass actor_attribute_equals(:role, :admin) do
      authorize_if action_type(:read)
    end

    policy action(:start) do
      authorize_if Basa.Witness.Checks.TransactionParty
    end

    policy action_type(:read) do
      authorize_if expr(exists(transaction.parties, user_id == ^actor(:id)))
    end

    policy action([:complete, :advance, :fail]) do
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

    attribute :provider, :atom, allow_nil?: false, public?: true
    attribute :state, :binary, allow_nil?: false

    attribute :status, :atom do
      constraints one_of: [:pending, :signed, :failed]
      default :pending
      allow_nil? false
      public? true
    end

    attribute :failure, :string, public?: true

    attribute :provider_data, :map, default: %{}, allow_nil?: false, sensitive?: true

    attribute :cms, :binary
    attribute :subject, :string, public?: true
    attribute :issuer, :string, public?: true
    attribute :serial, :string, public?: true
    attribute :signing_time, :utc_datetime, public?: true
    attribute :test, :boolean, default: false, allow_nil?: false, public?: true
    attribute :name_matches, :boolean, public?: true

    attribute :qualification, :atom do
      constraints one_of: [:unchecked, :qualified, :not_qualified]
      default :unchecked
      allow_nil? false
      public? true
    end

    attribute :qualification_level, :string, public?: true
    attribute :qualification_indication, :string, public?: true
    attribute :qualification_report, :map
    attribute :qualification_checked_at, :utc_datetime_usec, public?: true

    attribute :signed_at, :utc_datetime_usec, public?: true
    create_timestamp :inserted_at, public?: true
  end

  relationships do
    belongs_to :transaction, Basa.Witness.Transaction, allow_nil?: false, public?: true
    belongs_to :user, Basa.Accounts.User, allow_nil?: false, public?: true
  end

  identities do
    identity :unique_state, [:state]
  end
end
