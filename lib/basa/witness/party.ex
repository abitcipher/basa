defmodule Basa.Witness.Party do
  use Ash.Resource,
    otp_app: :basa,
    domain: Basa.Witness,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "witness_parties"
    repo Basa.Repo

    references do
      reference :transaction, on_delete: :delete
    end
  end

  actions do
    defaults [:read]

    create :add do
      accept [:role, :user_id]
      argument :transaction_id, :uuid, allow_nil?: false
      change set_attribute(:transaction_id, arg(:transaction_id))
    end

    update :set_legal_name do
      accept [:legal_name]
      require_atomic? false
      validate present(:legal_name)
      validate {Basa.Witness.Validations.TransactionStatus, statuses: [:draft]}
    end

    update :register_device do
      description """
      The device this party signs on (WebCrypto): its Ed25519 signing key and
      its X25519 key, to which the party's key share is sealed.
      """

      accept [:public_key, :box_key]
      require_atomic? false
      validate {Basa.Witness.Validations.TransactionStatus, statuses: [:draft]}

      validate fn changeset, _ ->
        case {Ash.Changeset.get_attribute(changeset, :public_key),
              Ash.Changeset.get_attribute(changeset, :box_key)} do
          {<<_::binary-size(32)>>, <<_::binary-size(32)>>} ->
            :ok

          _ ->
            {:error,
             field: :public_key, message: "needs a 32-byte signing key and a 32-byte box key"}
        end
      end
    end

    update :record_signature do
      accept [:signature, :signed_at]
    end
  end

  policies do
    bypass actor_attribute_equals(:role, :admin) do
      authorize_if always()
    end

    policy action_type(:read) do
      authorize_if expr(exists(transaction.parties, user_id == ^actor(:id)))
    end

    policy action([:set_legal_name, :register_device]) do
      authorize_if expr(user_id == ^actor(:id))
    end

    policy action([:add, :record_signature]) do
      forbid_if always()
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :role, :atom do
      constraints one_of: [:offeror, :acceptor]
      allow_nil? false
      public? true
    end

    attribute :legal_name, :string, public?: true, constraints: [max_length: 200]

    attribute :public_key, :binary, public?: true

    attribute :box_key, :binary, public?: true
    attribute :signature, :binary, public?: true
    attribute :signed_at, :utc_datetime_usec, public?: true

    timestamps()
  end

  relationships do
    belongs_to :transaction, Basa.Witness.Transaction, allow_nil?: false
    belongs_to :user, Basa.Accounts.User, allow_nil?: false, public?: true
  end

  identities do
    identity :one_per_role, [:transaction_id, :role]
  end
end
