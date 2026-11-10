defmodule Basa.Repo.Migrations.AddBasaDomain do
  use Ecto.Migration

  def up do
    create table(:attendants, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :name, :text, null: false
      add :role, :text, null: false, default: "assistant"
      add :phone, :text
      add :telegram_username, :text
      add :bio, :text

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :updated_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :owner_id,
          references(:users,
            column: :id,
            name: "attendants_owner_id_fkey",
            type: :uuid,
            prefix: "public",
            on_delete: :delete_all
          ),
          null: false
    end

    create table(:basket_attendants, primary_key: false) do
      add :basket_id, :uuid, null: false, primary_key: true

      add :attendant_id,
          references(:attendants,
            column: :id,
            name: "basket_attendants_attendant_id_fkey",
            type: :uuid,
            prefix: "public",
            on_delete: :delete_all
          ), primary_key: true, null: false
    end

    create table(:basket_items, primary_key: false) do
      add :basket_id, :uuid, null: false, primary_key: true
      add :item_id, :uuid, null: false, primary_key: true
    end

    create table(:bookings, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :starts_at, :utc_datetime_usec, null: false
      add :ends_at, :utc_datetime_usec, null: false
      add :status, :text, null: false, default: "pending"
      add :owner_id, :uuid, null: false
      add :units, :bigint, null: false
      add :price_amount, :decimal, null: false
      add :currency, :text, null: false
      add :note, :text
      add :completed_at, :utc_datetime_usec

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :updated_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :lot_id, :uuid, null: false

      add :lessee_id,
          references(:users,
            column: :id,
            name: "bookings_lessee_id_fkey",
            type: :uuid,
            prefix: "public",
            on_delete: :restrict
          ),
          null: false
    end

    create index(:bookings, [:lessee_id, :starts_at])

    create index(:bookings, [:owner_id, :starts_at])

    create table(:catalog_models, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :brand, :text, null: false
      add :model, :text, null: false
      add :reference_url, :text
      add :market_price, :decimal
      add :market_price_currency, :text
      add :market_price_source, :text
      add :market_price_at, :utc_datetime_usec

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :updated_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :category_id, :uuid
    end

    create unique_index(:catalog_models, [:brand, :model],
             name: "catalog_models_unique_brand_model_index"
           )

    create table(:categories, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
    end

    alter table(:catalog_models) do
      modify :category_id,
             references(:categories,
               column: :id,
               name: "catalog_models_category_id_fkey",
               type: :uuid,
               prefix: "public",
               on_delete: :nilify_all
             )
    end

    alter table(:categories) do
      add :slug, :text, null: false
      add :name, :map, null: false
      add :kind, :text, null: false
      add :parent_slug, :text
      add :attr_schema, :map, default: %{}
      add :position, :bigint, default: 0

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :updated_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
    end

    create unique_index(:categories, [:slug], name: "categories_unique_slug_index")

    create table(:claims, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :resource_type, :text, null: false
      add :resource_id, :uuid, null: false
      add :owner_id, :uuid, null: false
      add :starts_at, :"timestamptz(6)", null: false
      add :ends_at, :"timestamptz(6)", null: false
      add :active, :boolean, null: false, default: true

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :updated_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :booking_id,
          references(:bookings,
            column: :id,
            name: "claims_booking_id_fkey",
            type: :uuid,
            prefix: "public",
            on_delete: :delete_all
          ),
          null: false
    end

    create index(:claims, [:owner_id, :starts_at])

    execute("""
    ALTER TABLE claims ADD CONSTRAINT claims_no_overlap
    EXCLUDE USING gist (
      resource_type WITH =,
      resource_id WITH =,
      tstzrange(starts_at, ends_at, '[)') WITH &&
    ) WHERE (active)
    """)

    create table(:items, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
    end

    alter table(:basket_items) do
      modify :item_id,
             references(:items,
               column: :id,
               name: "basket_items_item_id_fkey",
               type: :uuid,
               prefix: "public",
               on_delete: :delete_all
             )
    end

    alter table(:items) do
      add :title, :text, null: false
      add :description, :text
      add :brand, :text
      add :model, :text
      add :condition, :text, default: "good"
      add :estimated_value, :decimal
      add :currency, :text, default: "UAH"
      add :attrs, :map, default: %{}
      add :photos, {:array, :text}, default: []
      add :ai_suggestion, :map

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :updated_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :owner_id,
          references(:users,
            column: :id,
            name: "items_owner_id_fkey",
            type: :uuid,
            prefix: "public",
            on_delete: :delete_all
          ),
          null: false

      add :category_id,
          references(:categories,
            column: :id,
            name: "items_category_id_fkey",
            type: :uuid,
            prefix: "public",
            on_delete: :nilify_all
          )

      add :catalog_model_id,
          references(:catalog_models,
            column: :id,
            name: "items_catalog_model_id_fkey",
            type: :uuid,
            prefix: "public",
            on_delete: :nilify_all
          )
    end

    create table(:lots, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
    end

    alter table(:bookings) do
      modify :lot_id,
             references(:lots,
               column: :id,
               name: "bookings_lot_id_fkey",
               type: :uuid,
               prefix: "public",
               on_delete: :restrict
             )
    end

    alter table(:lots) do
      add :title, :text, null: false
      add :description, :text
      add :price_amount, :decimal, null: false
      add :currency, :text, null: false, default: "UAH"
      add :price_unit, :text, null: false, default: "hour"
      add :slot_minutes, :bigint
      add :min_units, :bigint, null: false, default: 1
      add :max_units, :bigint
      add :lead_time_hours, :bigint, null: false, default: 0
      add :buffer_minutes, :bigint, null: false, default: 0
      add :booking_mode, :text, null: false, default: "instant"
      add :cancellation_hours, :bigint, null: false, default: 24
      add :weekly_hours, :map, default: %{}
      add :timezone, :text, null: false, default: "Europe/Kyiv"
      add :review_note, :text
      add :published_at, :utc_datetime_usec

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :updated_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :state, :text, null: false, default: "draft"

      add :owner_id,
          references(:users,
            column: :id,
            name: "lots_owner_id_fkey",
            type: :uuid,
            prefix: "public",
            on_delete: :delete_all
          ),
          null: false

      add :basket_id, :uuid, null: false
      add :room_id, :uuid, null: false
    end

    create index(:lots, [:state])

    create table(:offer_baskets, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
    end

    alter table(:basket_attendants) do
      modify :basket_id,
             references(:offer_baskets,
               column: :id,
               name: "basket_attendants_basket_id_fkey",
               type: :uuid,
               prefix: "public",
               on_delete: :delete_all
             )
    end

    alter table(:basket_items) do
      modify :basket_id,
             references(:offer_baskets,
               column: :id,
               name: "basket_items_basket_id_fkey",
               type: :uuid,
               prefix: "public",
               on_delete: :delete_all
             )
    end

    alter table(:lots) do
      modify :basket_id,
             references(:offer_baskets,
               column: :id,
               name: "lots_basket_id_fkey",
               type: :uuid,
               prefix: "public",
               on_delete: :restrict
             )
    end

    alter table(:offer_baskets) do
      add :title, :text, null: false
      add :description, :text
      add :service_type, :text, null: false, default: "equipment_rental"

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :updated_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :owner_id,
          references(:users,
            column: :id,
            name: "offer_baskets_owner_id_fkey",
            type: :uuid,
            prefix: "public",
            on_delete: :delete_all
          ),
          null: false
    end

    create table(:rooms, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
    end

    alter table(:lots) do
      modify :room_id,
             references(:rooms,
               column: :id,
               name: "lots_room_id_fkey",
               type: :uuid,
               prefix: "public",
               on_delete: :restrict
             )
    end

    alter table(:rooms) do
      add :title, :text, null: false
      add :description, :text
      add :city, :text, null: false
      add :address, :text
      add :lat, :float, null: false
      add :lng, :float, null: false
      add :placement, :text, null: false, default: "above_ground"
      add :mobile, :boolean, null: false, default: false
      add :service_radius_km, :bigint
      add :capacity, :bigint
      add :attrs, :map, default: %{}
      add :photos, {:array, :text}, default: []

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :updated_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :owner_id,
          references(:users,
            column: :id,
            name: "rooms_owner_id_fkey",
            type: :uuid,
            prefix: "public",
            on_delete: :delete_all
          ),
          null: false

      add :category_id,
          references(:categories,
            column: :id,
            name: "rooms_category_id_fkey",
            type: :uuid,
            prefix: "public",
            on_delete: :nilify_all
          )
    end

    create index(:rooms, [:city])

    execute("""
    CREATE INDEX rooms_geo_index ON rooms
    USING gist ((ST_SetSRID(ST_MakePoint(lng, lat), 4326)::geography))
    """)

    alter table(:users) do
      add :display_name, :text
      add :phone, :text
      add :phone_verified_at, :utc_datetime_usec
      add :telegram_id, :bigint
      add :telegram_username, :text
      add :locale, :text, null: false, default: "uk"
      add :role, :text, null: false, default: "user"
    end

    create unique_index(:users, [:telegram_id], name: "users_unique_telegram_id_index")
  end

  def down do
    drop_if_exists unique_index(:users, [:telegram_id], name: "users_unique_telegram_id_index")

    alter table(:users) do
      remove :role
      remove :locale
      remove :telegram_username
      remove :telegram_id
      remove :phone_verified_at
      remove :phone
      remove :display_name
    end

    execute("""
    DROP INDEX IF EXISTS rooms_geo_index
    """)

    drop_if_exists index(:rooms, [:city])

    drop constraint(:rooms, "rooms_category_id_fkey")

    drop constraint(:rooms, "rooms_owner_id_fkey")

    alter table(:rooms) do
      remove :category_id
      remove :owner_id
      remove :updated_at
      remove :inserted_at
      remove :photos
      remove :attrs
      remove :capacity
      remove :service_radius_km
      remove :mobile
      remove :placement
      remove :lng
      remove :lat
      remove :address
      remove :city
      remove :description
      remove :title
    end

    drop constraint(:lots, "lots_room_id_fkey")

    drop constraint(:lots, "lots_basket_id_fkey")

    drop constraint(:lots, "lots_owner_id_fkey")

    alter table(:lots) do
      modify :room_id, :uuid
    end

    drop table(:rooms)

    drop constraint(:offer_baskets, "offer_baskets_owner_id_fkey")

    alter table(:offer_baskets) do
      remove :owner_id
      remove :updated_at
      remove :inserted_at
      remove :service_type
      remove :description
      remove :title
    end

    alter table(:lots) do
      modify :basket_id, :uuid
    end

    drop constraint(:basket_items, "basket_items_item_id_fkey")

    drop constraint(:basket_items, "basket_items_basket_id_fkey")

    alter table(:basket_items) do
      modify :basket_id, :uuid
    end

    drop constraint(:basket_attendants, "basket_attendants_attendant_id_fkey")

    drop constraint(:basket_attendants, "basket_attendants_basket_id_fkey")

    alter table(:basket_attendants) do
      modify :basket_id, :uuid
    end

    drop table(:offer_baskets)

    drop_if_exists index(:lots, [:state])

    alter table(:lots) do
      remove :room_id
      remove :basket_id
      remove :owner_id
      remove :state
      remove :updated_at
      remove :inserted_at
      remove :published_at
      remove :review_note
      remove :timezone
      remove :weekly_hours
      remove :cancellation_hours
      remove :booking_mode
      remove :buffer_minutes
      remove :lead_time_hours
      remove :max_units
      remove :min_units
      remove :slot_minutes
      remove :price_unit
      remove :currency
      remove :price_amount
      remove :description
      remove :title
    end

    drop constraint(:bookings, "bookings_lessee_id_fkey")

    drop constraint(:bookings, "bookings_lot_id_fkey")

    alter table(:bookings) do
      modify :lot_id, :uuid
    end

    drop table(:lots)

    drop constraint(:items, "items_catalog_model_id_fkey")

    drop constraint(:items, "items_category_id_fkey")

    drop constraint(:items, "items_owner_id_fkey")

    alter table(:items) do
      remove :catalog_model_id
      remove :category_id
      remove :owner_id
      remove :updated_at
      remove :inserted_at
      remove :ai_suggestion
      remove :photos
      remove :attrs
      remove :currency
      remove :estimated_value
      remove :condition
      remove :model
      remove :brand
      remove :description
      remove :title
    end

    alter table(:basket_items) do
      modify :item_id, :uuid
    end

    drop table(:items)

    execute("""
    ALTER TABLE claims DROP CONSTRAINT IF EXISTS claims_no_overlap
    """)

    drop_if_exists index(:claims, [:owner_id, :starts_at])

    drop constraint(:claims, "claims_booking_id_fkey")

    drop table(:claims)

    drop_if_exists unique_index(:categories, [:slug], name: "categories_unique_slug_index")

    alter table(:categories) do
      remove :updated_at
      remove :inserted_at
      remove :position
      remove :attr_schema
      remove :parent_slug
      remove :kind
      remove :name
      remove :slug
    end

    drop constraint(:catalog_models, "catalog_models_category_id_fkey")

    alter table(:catalog_models) do
      modify :category_id, :uuid
    end

    drop table(:categories)

    drop_if_exists unique_index(:catalog_models, [:brand, :model],
                     name: "catalog_models_unique_brand_model_index"
                   )

    drop table(:catalog_models)

    drop_if_exists index(:bookings, [:owner_id, :starts_at])

    drop_if_exists index(:bookings, [:lessee_id, :starts_at])

    drop table(:bookings)

    drop table(:basket_items)

    drop table(:basket_attendants)

    drop constraint(:attendants, "attendants_owner_id_fkey")

    drop table(:attendants)
  end
end
