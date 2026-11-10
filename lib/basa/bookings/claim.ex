defmodule Basa.Bookings.Claim do
  use Ash.Resource,
    otp_app: :basa,
    domain: Basa.Bookings,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "claims"
    repo Basa.Repo

    references do
      reference :booking, on_delete: :delete
    end

    exclusion_constraint_names [
      {:starts_at, "claims_no_overlap", "this slot was just taken"}
    ]

    custom_statements do
      statement :claims_no_overlap do
        up """
        ALTER TABLE claims ADD CONSTRAINT claims_no_overlap
        EXCLUDE USING gist (
          resource_type WITH =,
          resource_id WITH =,
          tstzrange(starts_at, ends_at, '[)') WITH &&
        ) WHERE (active)
        """

        down "ALTER TABLE claims DROP CONSTRAINT IF EXISTS claims_no_overlap"
      end
    end

    custom_indexes do
      index [:owner_id, :starts_at]
    end
  end

  actions do
    defaults [:read]

    create :create do
      primary? true
      accept [:booking_id, :owner_id, :resource_type, :resource_id, :starts_at, :ends_at]
    end

    update :release do
      accept []
      change set_attribute(:active, false)
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if expr(owner_id == ^actor(:id))
    end

    policy action_type([:create, :update]) do
      forbid_if always()
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :resource_type, :atom do
      constraints one_of: [:room, :item, :attendant]
      allow_nil? false
      public? true
    end

    attribute :resource_id, :uuid, allow_nil?: false, public?: true
    attribute :owner_id, :uuid, allow_nil?: false, public?: true
    attribute :starts_at, AshPostgres.TimestamptzUsec, allow_nil?: false, public?: true
    attribute :ends_at, AshPostgres.TimestamptzUsec, allow_nil?: false, public?: true
    attribute :active, :boolean, default: true, allow_nil?: false, public?: true
    timestamps()
  end

  relationships do
    belongs_to :booking, Basa.Bookings.Booking, allow_nil?: false
  end
end
