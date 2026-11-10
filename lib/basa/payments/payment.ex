defmodule Basa.Payments.Payment do
  use Ash.Resource,
    otp_app: :basa,
    domain: Basa.Payments,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshTypescript.Resource]

  postgres do
    table "payments"
    repo Basa.Repo

    references do
      reference :user, on_delete: :restrict
      reference :booking, on_delete: :nilify
      reference :lot, on_delete: :nilify
    end

    custom_indexes do
      index [:provider_payment_id], unique: true
      index [:user_id, :inserted_at]
    end
  end

  typescript do
    type_name("Payment")
  end

  actions do
    read :admin_list do
      pagination offset?: true, required?: false, default_limit: 500, max_page_size: 1000
      prepare build(sort: [inserted_at: :desc])
    end

    defaults [:read]

    read :mine do
      filter expr(user_id == ^actor(:id))
      prepare build(sort: [inserted_at: :desc])
    end

    create :start_commission do
      argument :booking_id, :uuid, allow_nil?: false
      argument :amount, :decimal, allow_nil?: false, constraints: [min: 1]
      change relate_actor(:user)
      change Basa.Payments.Changes.PrepareCommission
      change Basa.Payments.Changes.OpenCheckout
    end

    create :start_premium do
      argument :lot_id, :uuid, allow_nil?: false

      argument :product, :atom,
        allow_nil?: false,
        constraints: [one_of: Basa.Payments.Products.products()]

      change relate_actor(:user)
      change Basa.Payments.Changes.PreparePremium
      change Basa.Payments.Changes.OpenCheckout
    end

    update :settle do
      accept [:status]
      require_atomic? false

      change fn changeset, _ ->
        if Ash.Changeset.get_attribute(changeset, :status) == :succeeded,
          do: Ash.Changeset.force_change_attribute(changeset, :paid_at, DateTime.utc_now()),
          else: changeset
      end
    end
  end

  policies do
    policy action(:admin_list) do
      authorize_if actor_attribute_equals(:role, :admin)
    end

    policy action_type(:read) do
      authorize_if expr(user_id == ^actor(:id))
      authorize_if actor_attribute_equals(:role, :admin)
    end

    policy action([:start_commission, :start_premium]) do
      authorize_if actor_present()
    end

    policy action(:settle) do
      forbid_if always()
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :purpose, :atom do
      constraints one_of: [:commission, :premium]
      allow_nil? false
      public? true
    end

    attribute :product, :atom, public?: true
    attribute :amount, :decimal, allow_nil?: false, public?: true

    attribute :currency, :atom do
      constraints one_of: Basa.Money.currencies()
      allow_nil? false
      public? true
    end

    attribute :status, :atom do
      constraints one_of: [:pending, :succeeded, :failed, :cancelled, :expired]
      default :pending
      allow_nil? false
      public? true
    end

    attribute :provider_payment_id, :string, public?: true
    attribute :payment_url, :string, public?: true
    attribute :paid_at, :utc_datetime_usec, public?: true
    timestamps()
  end

  relationships do
    belongs_to :user, Basa.Accounts.User, allow_nil?: false
    belongs_to :booking, Basa.Bookings.Booking, public?: true
    belongs_to :lot, Basa.Catalog.Lot, public?: true
  end

  calculations do
    calculate :user_name, :string, expr(user.display_name), public?: true
    calculate :lot_title, :string, expr(lot.title), public?: true
  end
end
