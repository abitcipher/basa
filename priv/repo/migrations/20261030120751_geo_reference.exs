defmodule Basa.Repo.Migrations.GeoReference do
  use Ecto.Migration

  def up do
    create table(:geo_cities, primary_key: false) do
      add :id, :text, null: false, primary_key: true
      add :source, :text, null: false
      add :origin, :text, null: false, default: "seed"
      add :name, :text, null: false
      add :names, :map, default: %{}
      add :ascii_name, :text
      add :country_code, :text, null: false
      add :admin1, :text
      add :lat, :float, null: false
      add :lng, :float, null: false
      add :timezone, :text, null: false
      add :population, :bigint, default: 0
      add :picks, :bigint, null: false, default: 0
      add :raw, :map, default: %{}

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :updated_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
    end

    create index(:geo_cities, [:country_code])

    create index(:geo_cities, ["lower(name)"], name: "geo_cities_lower_name_index")

    execute("""
    CREATE INDEX geo_cities_geo_index ON geo_cities
    USING gist ((ST_SetSRID(ST_MakePoint(lng, lat), 4326)::geography))
    """)

    create table(:geo_demand, primary_key: false) do
      add :id, :text, null: false, primary_key: true
      add :label, :text, null: false
      add :country_code, :text
      add :query, :text
      add :candidate, :map
      add :count, :bigint, null: false, default: 1
      add :status, :text, null: false, default: "open"
      add :last_searched_at, :utc_datetime_usec

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :updated_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
    end

    alter table(:rooms) do
      add :city_id,
          references(:geo_cities,
            column: :id,
            name: "rooms_city_id_fkey",
            type: :text,
            prefix: "public",
            on_delete: :nilify_all
          )
    end

    create index(:rooms, [:city_id])
  end

  def down do
    drop_if_exists index(:rooms, [:city_id])

    drop constraint(:rooms, "rooms_city_id_fkey")

    alter table(:rooms) do
      remove :city_id
    end

    drop table(:geo_demand)

    execute("""
    DROP INDEX IF EXISTS geo_cities_geo_index
    """)

    drop_if_exists index(:geo_cities, ["lower(name)"], name: "geo_cities_lower_name_index")

    drop_if_exists index(:geo_cities, [:country_code])

    drop table(:geo_cities)
  end
end
