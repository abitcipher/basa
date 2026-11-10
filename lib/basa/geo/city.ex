defmodule Basa.Geo.City do
  use Ash.Resource,
    otp_app: :basa,
    domain: Basa.Geo,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  @fields [
    :id,
    :source,
    :name,
    :names,
    :ascii_name,
    :country_code,
    :admin1,
    :lat,
    :lng,
    :timezone,
    :population,
    :raw
  ]

  postgres do
    table "geo_cities"
    repo Basa.Repo

    custom_indexes do
      index [:country_code]
      index ["lower(name)"], name: "geo_cities_lower_name_index"
    end

    custom_statements do
      statement :geo_cities_geo_index do
        up """
        CREATE INDEX geo_cities_geo_index ON geo_cities
        USING gist ((ST_SetSRID(ST_MakePoint(lng, lat), 4326)::geography))
        """

        down "DROP INDEX IF EXISTS geo_cities_geo_index"
      end
    end
  end

  actions do
    defaults [:read]

    create :import do
      accept @fields ++ [:origin, :picks]
      upsert? true
      upsert_fields @fields -- [:id]
      change Basa.Geo.Changes.Reindex
    end

    create :restore do
      accept @fields ++ [:origin, :picks]
      upsert? true
      upsert_fields (@fields -- [:id]) ++ [:origin, :picks]
      change Basa.Geo.Changes.Reindex
    end

    create :add do
      accept @fields ++ [:origin]
      upsert? true
      upsert_fields []
      change Basa.Geo.Changes.Reindex
    end

    update :pick do
      accept []
      require_atomic? false
      change atomic_update(:picks, expr(picks + 1))
      change Basa.Geo.Changes.Reindex
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if always()
    end

    policy action_type([:create, :update]) do
      forbid_if always()
    end
  end

  attributes do
    attribute :id, :string, primary_key?: true, allow_nil?: false, public?: true

    attribute :source, :atom do
      constraints one_of: [:geonames, :osm]
      allow_nil? false
      public? true
    end

    attribute :origin, :atom do
      constraints one_of: [:seed, :lessor, :admin]
      default :seed
      allow_nil? false
      public? true
    end

    attribute :name, :string, allow_nil?: false, public?: true
    attribute :names, :map, default: %{}, public?: true
    attribute :ascii_name, :string, public?: true
    attribute :country_code, :string, allow_nil?: false, public?: true
    attribute :admin1, :string, public?: true
    attribute :lat, :float, allow_nil?: false, public?: true
    attribute :lng, :float, allow_nil?: false, public?: true
    attribute :timezone, :string, allow_nil?: false, public?: true
    attribute :population, :integer, default: 0, public?: true
    attribute :picks, :integer, default: 0, allow_nil?: false, public?: true
    attribute :raw, :map, default: %{}, public?: true
    timestamps()
  end

  def display_name(%{names: names, name: name}, locale),
    do: (names || %{})[to_string(locale)] || (names || %{})["en"] || name

  def label(city, locale),
    do: "#{display_name(city, locale)}, #{Basa.Geo.Countries.name(city.country_code, locale)}"
end
