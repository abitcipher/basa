defmodule Basa.Witness.Transaction do
  use Ash.Resource,
    otp_app: :basa,
    domain: Basa.Witness,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "witness_transactions"
    repo Basa.Repo

    references do
      reference :booking, on_delete: :restrict
    end
  end

  actions do
    defaults [:read]

    create :open do
      description "A transaction for a booking: parties from the booking, a new data key, split and sealed."

      accept [
        :contract_type,
        :jurisdiction,
        :consumer,
        :template,
        :deposit_amount,
        :claims_window_days
      ]

      argument :booking_id, :uuid, allow_nil?: false

      change set_attribute(:booking_id, arg(:booking_id))
      change Basa.Witness.Changes.Open
    end

    update :update_terms do
      description "The offeror's terms while the contract is a draft (no deposit in a sale)."
      accept [:deposit_amount, :claims_window_days]
      require_atomic? false
      validate attribute_equals(:status, :draft)

      validate fn changeset, _ ->
        if changeset.data.contract_type == :sale and
             Ash.Changeset.get_attribute(changeset, :deposit_amount) != nil,
           do: {:error, field: :deposit_amount, message: "a sale has no deposit"},
           else: :ok
      end
    end

    update :declare_consumer do
      description "The acceptor says whether they act as a private person (consumer)."
      accept [:consumer]
      validate attribute_equals(:status, :draft)
    end

    update :prepare do
      description "Freezes the evidence, adds the contract PDF, builds the manifest and its BASA-HASH."
      require_atomic? false
      validate attribute_equals(:status, :draft)
      change Basa.Witness.Changes.Prepare
    end

    update :sign do
      description "A party's device signature over the BASA-HASH; the second one seals the transaction."
      require_atomic? false
      argument :signature, :binary, allow_nil?: false
      validate attribute_equals(:status, :signing)
      change Basa.Witness.Changes.Sign
    end

    update :apply_act do
      accept [:status, :returned_at, :claims_until, :closed_at, :deposit_status, :deposit_kept]
    end

    update :record_timestamp do
      accept [:timestamp_token, :timestamped_at]
    end

    update :confirm_in_person do
      description "Both parties' MEM attestations match (Basa.Witness.MemAttest)."
      change set_attribute(:mem_confirmed_at, &DateTime.utc_now/0)
    end

    update :confirm_qualified do
      description "Both parties signed with a qualified signature (Basa.Witness.QES)."
      change set_attribute(:qes_signed_at, &DateTime.utc_now/0)
    end

    update :cancel do
      description "Either party stops the contract before it is sealed."
      validate attribute_in(:status, [:draft, :signing])
      change set_attribute(:status, :cancelled)
    end
  end

  policies do
    bypass actor_attribute_equals(:role, :admin) do
      authorize_if always()
    end

    policy action(:open) do
      authorize_if Basa.Witness.Checks.BookingParty
    end

    policy action(:update_terms) do
      authorize_if expr(exists(parties, user_id == ^actor(:id) and role == :offeror))
    end

    policy action(:declare_consumer) do
      authorize_if expr(exists(parties, user_id == ^actor(:id) and role == :acceptor))
    end

    policy action([:record_timestamp, :apply_act]) do
      forbid_if always()
    end

    policy action([:prepare, :sign, :cancel]) do
      authorize_if expr(exists(parties, user_id == ^actor(:id)))
    end

    policy action_type(:read) do
      authorize_if expr(exists(parties, user_id == ^actor(:id)))
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :contract_type, :atom do
      constraints one_of: [:lease, :sale]
      default :lease
      allow_nil? false
      public? true
    end

    attribute :jurisdiction, :atom do
      constraints one_of: [:ua, :eu]
      allow_nil? false
      public? true
    end

    attribute :consumer, :boolean, default: false, allow_nil?: false, public?: true

    attribute :template, :string, allow_nil?: false, public?: true

    attribute :languages, {:array, :atom}, allow_nil?: false, public?: true

    attribute :deposit_amount, :decimal, public?: true, constraints: [min: 0]

    attribute :claims_window_days, :integer,
      default: 3,
      allow_nil?: false,
      public?: true,
      constraints: [min: 1, max: 60]

    attribute :status, :atom do
      constraints one_of: [
                    :draft,
                    :signing,
                    :sealed,
                    :active,
                    :returned,
                    :delivered,
                    :closed,
                    :claimed,
                    :settled,
                    :disputed,
                    :cancelled
                  ]

      default :draft
      allow_nil? false
      public? true
    end

    attribute :storage_mode, :atom do
      constraints one_of: [:plain, :encrypted]
      allow_nil? false
      public? true
    end

    attribute :recovery_sealed, :binary, allow_nil?: false, sensitive?: true

    attribute :manifest, :binary
    attribute :basa_hash, :binary, public?: true
    attribute :sealed_at, :utc_datetime_usec, public?: true

    attribute :returned_at, :utc_datetime_usec, public?: true
    attribute :claims_until, :utc_datetime_usec, public?: true
    attribute :closed_at, :utc_datetime_usec, public?: true

    attribute :deposit_status, :atom do
      constraints one_of: [:none, :held, :released, :kept, :partly_kept]
      default :none
      allow_nil? false
      public? true
    end

    attribute :deposit_kept, :decimal, public?: true

    attribute :timestamp_token, :binary
    attribute :timestamped_at, :utc_datetime_usec, public?: true

    attribute :mem_confirmed_at, :utc_datetime_usec, public?: true

    attribute :qes_signed_at, :utc_datetime_usec, public?: true

    timestamps()
  end

  relationships do
    belongs_to :booking, Basa.Bookings.Booking, allow_nil?: false, public?: true
    has_many :parties, Basa.Witness.Party, public?: true
    has_many :evidence, Basa.Witness.Evidence, sort: [position: :asc], public?: true
    has_many :key_shares, Basa.Witness.KeyShare
    has_many :access_logs, Basa.Witness.AccessLog
    has_many :acts, Basa.Witness.Act, sort: [sequence: :asc], public?: true
    has_many :authority_requests, Basa.Witness.AuthorityRequest
    has_many :mem_attestations, Basa.Witness.MemAttestation
    has_many :qualified_signatures, Basa.Witness.QualifiedSignature
  end

  identities do
    identity :one_per_booking, [:booking_id]
    identity :unique_basa_hash, [:basa_hash], nils_distinct?: true
  end
end
