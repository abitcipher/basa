defmodule Basa.Catalog.Room do
  use Ash.Resource,
    otp_app: :basa,
    domain: Basa.Catalog,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshTypescript.Resource]

  @fields [
    :title,
    :description,
    :city,
    :city_id,
    :address,
    :lat,
    :lng,
    :placement,
    :mobile,
    :service_radius_km,
    :capacity,
    :attrs,
    :photos,
    :category_id,
    :street_view,
    :entrance_photos
  ]

  @max_entrance 3

  def max_entrance_photos, do: @max_entrance

  postgres do
    table "rooms"
    repo Basa.Repo

    references do
      reference :owner, on_delete: :delete
      reference :category, on_delete: :nilify
      reference :geo_city, on_delete: :nilify
    end

    custom_indexes do
      index [:city]
      index [:city_id]
    end

    custom_statements do
      statement :rooms_geo_index do
        up """
        CREATE INDEX rooms_geo_index ON rooms
        USING gist ((ST_SetSRID(ST_MakePoint(lng, lat), 4326)::geography))
        """

        down "DROP INDEX IF EXISTS rooms_geo_index"
      end
    end
  end

  typescript do
    type_name("Room")
  end

  actions do
    defaults [:read, :destroy]

    read :mine do
      filter expr(owner_id == ^actor(:id))
      prepare build(sort: [updated_at: :desc])
    end

    create :create do
      primary? true
      accept @fields
      change relate_actor(:owner)
      change Basa.Catalog.Changes.SetCity
      change Basa.Catalog.Changes.ValidateAttrs
    end

    update :update do
      primary? true
      require_atomic? false
      accept @fields
      change Basa.Catalog.Changes.SetCity
      change Basa.Catalog.Changes.ValidateAttrs
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if relates_to_actor_via(:owner)
      authorize_if expr(exists(lots, state == :published))
    end

    policy action_type(:create) do
      authorize_if actor_present()
    end

    policy action_type([:update, :destroy]) do
      authorize_if relates_to_actor_via(:owner)
    end
  end

  changes do
    change {Basa.Search.Changes.Reindex, lots: :by_room}, on: [:update]
  end

  validations do
    validate present(:service_radius_km), where: [attribute_equals(:mobile, true)]

    validate compare(:lat, greater_than_or_equal_to: -90, less_than_or_equal_to: 90),
      where: present(:lat)

    validate compare(:lng, greater_than_or_equal_to: -180, less_than_or_equal_to: 180),
      where: present(:lng)

    validate fn changeset, context ->
      owner =
        Ash.Changeset.get_attribute(changeset, :owner_id) || (context.actor && context.actor.id)

      if Basa.StreetView.valid?(Ash.Changeset.get_attribute(changeset, :street_view), owner),
        do: :ok,
        else: {:error, field: :street_view, message: "is not a street view kept by BASA"}
    end

    validate fn changeset, context ->
      owner =
        Ash.Changeset.get_attribute(changeset, :owner_id) || (context.actor && context.actor.id)

      keys = Ash.Changeset.get_attribute(changeset, :entrance_photos) || []

      cond do
        length(keys) > @max_entrance ->
          {:error, field: :entrance_photos, message: "at most #{@max_entrance} photos"}

        not Enum.all?(keys, &(is_binary(&1) and String.starts_with?(&1, "entrance/#{owner}/"))) ->
          {:error, field: :entrance_photos, message: "must be the owner's own uploads"}

        true ->
          :ok
      end
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :title, :string do
      allow_nil? false
      public? true
      constraints max_length: 200
    end

    attribute :description, :string, public?: true
    attribute :city, :string, allow_nil?: false, public?: true
    attribute :address, :string, public?: true
    attribute :lat, :float, allow_nil?: false, public?: true
    attribute :lng, :float, allow_nil?: false, public?: true

    attribute :placement, :atom do
      constraints one_of: [:above_ground, :underground, :open_area]
      default :above_ground
      allow_nil? false
      public? true
    end

    attribute :mobile, :boolean, default: false, allow_nil?: false, public?: true
    attribute :service_radius_km, :integer, public?: true, constraints: [min: 1, max: 1000]
    attribute :capacity, :integer, public?: true, constraints: [min: 1]
    attribute :attrs, :map, default: %{}, public?: true
    attribute :photos, {:array, :string}, default: [], public?: true

    attribute :street_view, :map, public?: true

    attribute :entrance_photos, {:array, :string}, default: [], public?: true
    timestamps()
  end

  relationships do
    belongs_to :owner, Basa.Accounts.User, allow_nil?: false
    belongs_to :category, Basa.Catalog.Category, public?: true

    belongs_to :geo_city, Basa.Geo.City do
      source_attribute :city_id
      attribute_type :string
      public? true
    end

    has_many :lots, Basa.Catalog.Lot, destination_attribute: :room_id
  end

  calculations do
    calculate :photo_urls, {:array, :string}, fn records, _ ->
      Enum.map(records, fn r -> Enum.map(r.photos || [], &Basa.Storage.url/1) end)
    end do
      public? true
    end
  end

  def placement_marker(:above_ground), do: "∧ [•]"
  def placement_marker(:underground), do: "∨ [+]"
  def placement_marker(:open_area), do: "⊻ [⊕]"
end
