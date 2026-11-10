defmodule Basa.Witness.KeyShare do
  use Ash.Resource,
    otp_app: :basa,
    domain: Basa.Witness,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "witness_key_shares"
    repo Basa.Repo

    references do
      reference :transaction, on_delete: :delete
    end
  end

  actions do
    defaults [:read]

    create :store do
      accept [:owner, :share, :act_id]
      argument :transaction_id, :uuid, allow_nil?: false
      change set_attribute(:transaction_id, arg(:transaction_id))
    end

    update :deliver do
      accept [:sealed_share, :share, :delivered_at]
    end
  end

  policies do
    policy always() do
      forbid_if always()
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :owner, :atom do
      constraints one_of: [:offeror, :acceptor, :basa]
      allow_nil? false
    end

    attribute :share, :binary, sensitive?: true

    attribute :sealed_share, :binary
    attribute :delivered_at, :utc_datetime_usec

    timestamps()
  end

  relationships do
    belongs_to :transaction, Basa.Witness.Transaction, allow_nil?: false

    belongs_to :act, Basa.Witness.Act
  end

  identities do
    identity :one_per_owner, [:transaction_id, :act_id, :owner], nils_distinct?: false
  end
end
