defmodule Basa.Bookings.Booking do
  use Ash.Resource,
    otp_app: :basa,
    domain: Basa.Bookings,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshTypescript.Resource]

  postgres do
    table "bookings"
    repo Basa.Repo

    references do
      reference :lot, on_delete: :restrict
      reference :lessee, on_delete: :restrict
    end

    custom_indexes do
      index [:lessee_id, :starts_at]
      index [:owner_id, :starts_at]
    end
  end

  typescript do
    type_name("Booking")
  end

  actions do
    defaults [:read]

    action :schedule, {:array, :map} do
      description "The actor's bookings (as lessor) between two dates."
      argument :from, :date, allow_nil?: false
      argument :to, :date, allow_nil?: false

      constraints items: [
                    fields: [
                      id: [type: :uuid, allow_nil?: false],
                      lot_id: [type: :uuid, allow_nil?: false],
                      lot_title: [type: :string, allow_nil?: false],
                      room_title: [type: :string],
                      starts_at: [type: :utc_datetime, allow_nil?: false],
                      ends_at: [type: :utc_datetime, allow_nil?: false],
                      status: [type: :atom, allow_nil?: false],
                      lessee: [type: :string],
                      timezone: [type: :string, allow_nil?: false],
                      price_amount: [type: :decimal, allow_nil?: false],
                      currency: [type: :atom, allow_nil?: false]
                    ]
                  ]

      run {Basa.Bookings.Actions.Schedule, view: :bookings}
    end

    action :stats, :map do
      description "How the actor's offers did between two dates (as lessor)."
      argument :from, :date, allow_nil?: false
      argument :to, :date, allow_nil?: false

      constraints fields: [
                    currency: [type: :atom, allow_nil?: false],
                    offers: [
                      type: {:array, :map},
                      allow_nil?: false,
                      constraints: [
                        items: [
                          fields: [
                            lot_id: [type: :uuid, allow_nil?: false],
                            title: [type: :string, allow_nil?: false],
                            open_hours: [type: :integer, allow_nil?: false],
                            booked_hours: [type: :integer, allow_nil?: false],
                            occupancy: [type: :float, allow_nil?: false],
                            bookings: [type: :integer, allow_nil?: false],
                            earnings: [type: :decimal, allow_nil?: false],
                            currency: [type: :atom, allow_nil?: false]
                          ]
                        ]
                      ]
                    ],
                    weeks: [
                      type: {:array, :map},
                      allow_nil?: false,
                      constraints: [
                        items: [
                          fields: [
                            week: [type: :date, allow_nil?: false],
                            bookings: [type: :integer, allow_nil?: false],
                            earnings: [type: :decimal, allow_nil?: false]
                          ]
                        ]
                      ]
                    ]
                  ]

      run {Basa.Bookings.Actions.Schedule, view: :stats}
    end

    action :timeline, {:array, :map} do
      description "The actor's rooms, items and attendants with their booked time."
      argument :from, :date, allow_nil?: false
      argument :to, :date, allow_nil?: false

      constraints items: [
                    fields: [
                      id: [type: :uuid, allow_nil?: false],
                      type: [type: :atom, allow_nil?: false],
                      title: [type: :string, allow_nil?: false],
                      bookings: [
                        type: {:array, :map},
                        allow_nil?: false,
                        constraints: [
                          items: [
                            fields: [
                              booking_id: [type: :uuid, allow_nil?: false],
                              starts_at: [type: :utc_datetime, allow_nil?: false],
                              ends_at: [type: :utc_datetime, allow_nil?: false],
                              status: [type: :atom, allow_nil?: false],
                              lot_title: [type: :string, allow_nil?: false],
                              lessee: [type: :string]
                            ]
                          ]
                        ]
                      ]
                    ]
                  ]

      run {Basa.Bookings.Actions.Schedule, view: :resources}
    end

    read :mine do
      filter expr(lessee_id == ^actor(:id))
      prepare build(sort: [starts_at: :desc], load: [lot: [room: [:geo_city]]])
    end

    read :admin_list do
      pagination offset?: true, required?: false, default_limit: 500, max_page_size: 1000
      prepare build(sort: [starts_at: :desc])
    end

    read :incoming do
      filter expr(owner_id == ^actor(:id))
      prepare build(sort: [starts_at: :desc], load: [:lessee, lot: [room: [:geo_city]]])
    end

    create :book do
      accept [:lot_id, :starts_at, :ends_at, :note]
      change relate_actor(:lessee)
      change Basa.Bookings.Changes.PlaceBooking
    end

    update :confirm do
      require_atomic? false
      accept []
      validate attribute_equals(:status, :pending)
      change set_attribute(:status, :confirmed)
      change {Basa.Bookings.Changes.Notify, event: :confirmed}
    end

    update :decline do
      require_atomic? false
      accept []
      validate attribute_equals(:status, :pending)
      change set_attribute(:status, :declined)
      change Basa.Bookings.Changes.ReleaseClaims
      change {Basa.Bookings.Changes.Notify, event: :declined}
    end

    update :cancel do
      require_atomic? false
      accept []
      validate attribute_in(:status, [:pending, :confirmed])
      validate Basa.Bookings.Validations.CancellationWindow
      change set_attribute(:status, :cancelled)
      change Basa.Bookings.Changes.ReleaseClaims
      change {Basa.Bookings.Changes.Notify, event: :cancelled}
    end

    update :complete do
      require_atomic? false
      accept []
      validate attribute_equals(:status, :confirmed)
      change set_attribute(:status, :completed)
      change set_attribute(:completed_at, &DateTime.utc_now/0)
    end
  end

  policies do
    bypass action_type(:read) do
      authorize_if actor_attribute_equals(:role, :admin)
    end

    policy action(:admin_list) do
      authorize_if actor_attribute_equals(:role, :admin)
    end

    policy action_type(:read) do
      authorize_if expr(lessee_id == ^actor(:id))
      authorize_if expr(owner_id == ^actor(:id))
    end

    policy action(:book) do
      authorize_if actor_present()
    end

    policy action([:schedule, :timeline, :stats]) do
      authorize_if actor_present()
    end

    policy action([:confirm, :decline, :complete]) do
      authorize_if expr(owner_id == ^actor(:id))
    end

    policy action(:cancel) do
      authorize_if expr(lessee_id == ^actor(:id))
      authorize_if expr(owner_id == ^actor(:id))
    end
  end

  changes do
    change {Basa.Events.Changes.Publish, kind: :booking}, on: [:create, :update]
    change Basa.Bookings.Changes.NotifyOwner, on: [:update]
  end

  attributes do
    uuid_primary_key :id
    attribute :starts_at, :utc_datetime_usec, allow_nil?: false, public?: true
    attribute :ends_at, :utc_datetime_usec, allow_nil?: false, public?: true

    attribute :status, :atom do
      constraints one_of: [:pending, :confirmed, :declined, :cancelled, :completed]
      default :pending
      allow_nil? false
      public? true
    end

    attribute :owner_id, :uuid, allow_nil?: false, public?: true
    attribute :units, :integer, allow_nil?: false, public?: true
    attribute :price_amount, :decimal, allow_nil?: false, public?: true

    attribute :currency, :atom do
      constraints one_of: Basa.Money.currencies()
      allow_nil? false
      public? true
    end

    attribute :note, :string, public?: true, constraints: [max_length: 1000]
    attribute :completed_at, :utc_datetime_usec, public?: true
    timestamps()
  end

  relationships do
    belongs_to :lot, Basa.Catalog.Lot, allow_nil?: false, public?: true
    belongs_to :lessee, Basa.Accounts.User, allow_nil?: false, public?: true
    has_many :claims, Basa.Bookings.Claim
  end

  calculations do
    calculate :lot_title, :string, expr(lot.title), public?: true
    calculate :lessee_name, :string, expr(lessee.display_name), public?: true
    calculate :lessor_name, :string, expr(lot.owner.display_name), public?: true
  end
end
