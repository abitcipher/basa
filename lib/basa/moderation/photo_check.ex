defmodule Basa.Moderation.PhotoCheck do
  use Ash.Resource,
    otp_app: :basa,
    domain: Basa.Moderation,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "photo_checks"
    repo Basa.Repo

    references do
      reference :owner, on_delete: :nilify
    end

    custom_indexes do
      index [:verdict, :review]
    end
  end

  actions do
    defaults [:read]

    create :queue do
      accept [:key]
      upsert? true
      upsert_identity :unique_key
      upsert_fields [:status, :updated_at]
      change set_attribute(:status, :pending)
      change Basa.Moderation.Changes.OwnerFromKey
    end

    update :record do
      accept [:scores, :verdict, :reasons, :level, :models]
      change set_attribute(:status, :checked)
      change set_attribute(:error, nil)
      change set_attribute(:checked_at, &DateTime.utc_now/0)
    end

    update :requeue do
      change set_attribute(:status, :pending)
    end

    update :fail do
      accept [:error]
      change set_attribute(:status, :failed)
    end

    update :review do
      require_atomic? false
      argument :decision, :atom, allow_nil?: false, constraints: [one_of: [:kept, :removed]]
      change set_attribute(:review, arg(:decision))
      change set_attribute(:reviewed_at, &DateTime.utc_now/0)
      change Basa.Rules.Changes.Stamp
    end

    read :to_review do
      filter expr(status == :checked and verdict in [:flag, :block] and is_nil(review))
      prepare build(sort: [checked_at: :desc])
    end

    read :mine_hidden do
      filter expr(
               owner_id == ^actor(:id) and
                 ((verdict == :block and (is_nil(review) or review != :kept)) or
                    review == :removed)
             )

      prepare build(sort: [checked_at: :desc])
    end
  end

  policies do
    bypass actor_attribute_equals(:role, :admin) do
      authorize_if always()
    end

    policy action(:mine_hidden) do
      authorize_if actor_present()
    end

    policy action_type(:read) do
      authorize_if relates_to_actor_via(:owner)
    end

    policy action([:queue, :requeue, :record, :fail, :review]) do
      forbid_if always()
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :key, :string, allow_nil?: false, public?: true

    attribute :status, :atom,
      allow_nil?: false,
      default: :pending,
      public?: true,
      constraints: [one_of: [:pending, :checked, :failed]]

    attribute :verdict, :atom, public?: true, constraints: [one_of: [:ok, :flag, :block]]
    attribute :reasons, {:array, :string}, default: [], public?: true
    attribute :scores, :map, public?: true
    attribute :level, :integer, public?: true
    attribute :models, {:array, :string}, default: [], public?: true
    attribute :error, :string, public?: true
    attribute :checked_at, :utc_datetime_usec, public?: true

    attribute :review, :atom, public?: true, constraints: [one_of: [:kept, :removed]]
    attribute :reviewed_at, :utc_datetime_usec, public?: true
    attribute :updated_by_email, :string, public?: true
    timestamps()
  end

  relationships do
    belongs_to :owner, Basa.Accounts.User, public?: true
  end

  calculations do
    calculate :hidden?,
              :boolean,
              expr(
                if review == :removed or (verdict == :block and is_nil(review)),
                  do: true,
                  else: false
              )
  end

  identities do
    identity :unique_key, [:key]
  end
end
