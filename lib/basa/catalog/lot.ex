defmodule Basa.Catalog.Lot do
  use Ash.Resource,
    otp_app: :basa,
    domain: Basa.Catalog,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshStateMachine, AshTypescript.Resource, AshJsonApi.Resource],
    notifiers: [Ash.Notifier.PubSub]

  require Ash.Query

  @fields [
    :deal,
    :title,
    :description,
    :price_amount,
    :currency,
    :price_unit,
    :slot_minutes,
    :min_units,
    :max_units,
    :lead_time_hours,
    :buffer_minutes,
    :booking_mode,
    :cancellation_hours,
    :weekly_hours,
    :timezone
  ]

  json_api do
    type "lot"
  end

  postgres do
    table "lots"
    repo Basa.Repo

    references do
      reference :owner, on_delete: :delete
      reference :basket, on_delete: :restrict
      reference :room, on_delete: :restrict
    end

    custom_indexes do
      index [:state]
    end
  end

  state_machine do
    initial_states [:draft]
    default_initial_state :draft

    transitions do
      transition :submit, from: :draft, to: [:published, :under_review, :draft]
      transition :approve, from: :under_review, to: :published
      transition :reject, from: :under_review, to: :draft
      transition :archive, from: [:draft, :under_review, :published], to: :archived
    end
  end

  typescript do
    type_name("Lot")
  end

  actions do
    defaults [:read]

    action :availability, {:array, :map} do
      description "Slots per local day of the lot, free or taken."
      argument :lot_id, :uuid, allow_nil?: false
      argument :from, :date, allow_nil?: false
      argument :days, :integer, default: 42, constraints: [min: 1, max: 62]

      constraints items: [
                    fields: [
                      date: [type: :date, allow_nil?: false],
                      free: [type: :integer, allow_nil?: false],
                      total: [type: :integer, allow_nil?: false],
                      slots: [
                        type: {:array, :map},
                        allow_nil?: false,
                        constraints: [
                          items: [
                            fields: [
                              starts_at: [type: :utc_datetime, allow_nil?: false],
                              ends_at: [type: :utc_datetime, allow_nil?: false],
                              free: [type: :boolean, allow_nil?: false]
                            ]
                          ]
                        ]
                      ]
                    ]
                  ]

      run Basa.Catalog.Actions.Availability
    end

    read :mine do
      filter expr(owner_id == ^actor(:id) and state != :archived)
      prepare build(sort: [updated_at: :desc], load: [:room, basket: [:items]])
    end

    read :search do
      pagination offset?: true, required?: false, default_limit: 50, max_page_size: 100
      argument :city, :string
      argument :city_id, :string
      argument :q, :string
      argument :service_type, :atom
      argument :deal, :atom, constraints: [one_of: [:lease, :sale]]
      argument :lat, :float
      argument :lng, :float
      argument :radius_km, :integer, default: 25
      argument :region_country, :string
      argument :region_admin1, :string
      argument :currency, :atom, constraints: [one_of: Basa.Money.currencies()]
      argument :price_max, :decimal, constraints: [min: 0]
      argument :mobile, :boolean, default: false
      argument :free_on, :date

      argument :sort, :atom,
        default: :recommended,
        constraints: [one_of: [:recommended, :price_asc, :price_desc, :newest]]

      argument :ids, {:array, :uuid}

      prepare fn query, _ ->
        case Ash.Query.get_argument(query, :ids) do
          nil -> query
          ids -> Ash.Query.filter(query, id in ^ids)
        end
      end

      filter expr(state == :published)

      filter expr(
               is_nil(^arg(:city)) or
                 fragment("lower(?)", room.city) == fragment("lower(?)", ^arg(:city))
             )

      filter expr(is_nil(^arg(:city_id)) or room.city_id == ^arg(:city_id))

      filter expr(
               is_nil(^arg(:region_country)) or
                 (room.geo_city.country_code == ^arg(:region_country) and
                    (is_nil(^arg(:region_admin1)) or
                       room.geo_city.admin1 == ^arg(:region_admin1)))
             )

      filter expr(
               is_nil(^arg(:q)) or
                 contains(fragment("lower(?)", title), fragment("lower(?)", ^arg(:q))) or
                 contains(
                   fragment("lower(coalesce(?, ''))", description),
                   fragment("lower(?)", ^arg(:q))
                 )
             )

      filter expr(is_nil(^arg(:service_type)) or basket.service_type == ^arg(:service_type))
      filter expr(is_nil(^arg(:deal)) or deal == ^arg(:deal))

      filter expr(
               is_nil(^arg(:lat)) or is_nil(^arg(:lng)) or
                 fragment(
                   "ST_DWithin(ST_SetSRID(ST_MakePoint(?, ?), 4326)::geography, ST_SetSRID(ST_MakePoint(?, ?), 4326)::geography, ? * 1000 + coalesce(?, 0) * 1000)",
                   room.lng,
                   room.lat,
                   ^arg(:lng),
                   ^arg(:lat),
                   ^arg(:radius_km),
                   room.service_radius_km
                 )
             )

      filter expr(is_nil(^arg(:currency)) or currency == ^arg(:currency))

      filter expr(
               is_nil(^arg(:price_max)) or is_nil(^arg(:currency)) or
                 price_amount <= ^arg(:price_max)
             )

      filter expr(^arg(:mobile) == false or room.mobile == true)

      prepare Basa.Catalog.Preparations.SearchSort
      prepare Basa.Catalog.Preparations.FreeOn
      prepare build(load: [:featured, room: [:geo_city], basket: [:items, :attendants]])
    end

    create :create do
      primary? true
      accept [:basket_id, :room_id | @fields]
      change relate_actor(:owner)
      validate Basa.Catalog.Validations.OwnsBasketAndRoom
      validate Basa.Catalog.Validations.LotRules
    end

    update :update do
      primary? true
      require_atomic? false
      accept [:basket_id, :room_id | @fields]
      validate Basa.Catalog.Validations.OwnsBasketAndRoom
      validate Basa.Catalog.Validations.LotRules
      validate attribute_does_not_equal(:state, :archived)
    end

    update :submit do
      require_atomic? false
      accept []
      change Basa.Catalog.Changes.ReviewLot
    end

    update :approve do
      require_atomic? false
      accept []
      change transition_state(:published)
      change set_attribute(:published_at, &DateTime.utc_now/0)
      change set_attribute(:review_note, nil)
    end

    update :reject do
      require_atomic? false
      argument :review_note, :string, allow_nil?: false
      change transition_state(:draft)
      change set_attribute(:review_note, arg(:review_note))
    end

    update :feature do
      accept [:featured_until]
    end

    update :archive do
      require_atomic? false
      accept []
      change transition_state(:archived)
    end
  end

  policies do
    bypass actor_attribute_equals(:role, :admin) do
      authorize_if always()
    end

    policy action_type(:read) do
      authorize_if expr(state == :published)
      authorize_if relates_to_actor_via(:owner)
    end

    policy action_type(:create) do
      authorize_if actor_present()
    end

    policy action(:availability) do
      authorize_if always()
    end

    policy action([:update, :submit, :archive]) do
      authorize_if relates_to_actor_via(:owner)
    end

    policy action([:approve, :reject, :feature]) do
      forbid_if always()
    end
  end

  pub_sub do
    module BasaWeb.Endpoint
    prefix "lot"
    publish_all :update, ["updated", :id]
  end

  changes do
    change {Basa.Events.Changes.Publish, kind: :lot}, on: [:create, :update]
    change {Basa.Search.Changes.Reindex, lots: :self}, on: [:create, :update]
  end

  attributes do
    uuid_primary_key :id

    attribute :title, :string do
      allow_nil? false
      public? true
      constraints max_length: 200
    end

    attribute :description, :string, public?: true

    attribute :deal, :atom do
      constraints one_of: [:lease, :sale]
      default :lease
      allow_nil? false
      public? true
    end

    attribute :price_amount, :decimal do
      allow_nil? false
      public? true
      constraints min: 0
    end

    attribute :currency, :atom do
      constraints one_of: Basa.Money.currencies()
      default :UAH
      allow_nil? false
      public? true
    end

    attribute :price_unit, :atom do
      constraints one_of: [:hour, :day, :slot]
      default :hour
      allow_nil? false
      public? true
    end

    attribute :slot_minutes, :integer, public?: true, constraints: [min: 15]

    attribute :min_units, :integer,
      default: 1,
      allow_nil?: false,
      public?: true,
      constraints: [min: 1]

    attribute :max_units, :integer, public?: true, constraints: [min: 1]

    attribute :lead_time_hours, :integer,
      default: 0,
      allow_nil?: false,
      public?: true,
      constraints: [min: 0]

    attribute :buffer_minutes, :integer,
      default: 0,
      allow_nil?: false,
      public?: true,
      constraints: [min: 0]

    attribute :booking_mode, :atom do
      constraints one_of: [:instant, :request]
      default :instant
      allow_nil? false
      public? true
    end

    attribute :cancellation_hours, :integer, default: 24, allow_nil?: false, public?: true

    attribute :weekly_hours, :map, default: %{}, public?: true

    attribute :timezone, :string, default: "Europe/Kyiv", allow_nil?: false, public?: true
    attribute :review_note, :string, public?: true
    attribute :published_at, :utc_datetime_usec, public?: true
    attribute :featured_until, :utc_datetime_usec, public?: true
    timestamps()
  end

  relationships do
    belongs_to :owner, Basa.Accounts.User, allow_nil?: false
    belongs_to :basket, Basa.Catalog.OfferBasket, allow_nil?: false, public?: true
    belongs_to :room, Basa.Catalog.Room, allow_nil?: false, public?: true
    has_many :bookings, Basa.Bookings.Booking
  end

  calculations do
    calculate :featured, :boolean, expr(not is_nil(featured_until) and featured_until > now()),
      public?: true
  end
end
