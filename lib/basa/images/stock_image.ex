defmodule Basa.Images.StockImage do
  use Ash.Resource,
    otp_app: :basa,
    domain: Basa.Images,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "stock_images"
    repo Basa.Repo
  end

  actions do
    defaults [:read]

    create :cache do
      accept [
        :key,
        :sha256,
        :content_type,
        :byte_size,
        :width,
        :height,
        :source,
        :source_id,
        :title,
        :creator,
        :creator_url,
        :license,
        :license_version,
        :license_url,
        :landing_url,
        :original_url,
        :tags,
        :queries
      ]

      change set_attribute(:uses, 1)
    end

    update :used do
      require_atomic? false
      argument :query, :string

      change fn changeset, _ ->
        image = changeset.data
        query = Ash.Changeset.get_argument(changeset, :query)

        queries =
          if query in [nil, ""],
            do: image.queries,
            else: Enum.take(Enum.uniq(image.queries ++ [query]), -20)

        Ash.Changeset.force_change_attributes(changeset, uses: image.uses + 1, queries: queries)
      end
    end

    destroy :destroy do
      primary? true
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if always()
    end

    policy action_type([:create, :update, :destroy]) do
      forbid_if always()
    end
  end

  changes do
    change after_action(fn _changeset, image, _ ->
             Basa.Images.IndexWorker.enqueue(image.id)
             {:ok, image}
           end),
           on: [:create, :update]
  end

  attributes do
    uuid_primary_key :id

    attribute :key, :string, allow_nil?: false, public?: true
    attribute :sha256, :string, allow_nil?: false, public?: true
    attribute :content_type, :string, allow_nil?: false, public?: true
    attribute :byte_size, :integer, public?: true
    attribute :width, :integer, public?: true
    attribute :height, :integer, public?: true

    attribute :source, :atom do
      constraints one_of: [:openverse]
      allow_nil? false
      public? true
    end

    attribute :source_id, :string, allow_nil?: false, public?: true
    attribute :title, :string, public?: true
    attribute :creator, :string, public?: true
    attribute :creator_url, :string, public?: true
    attribute :license, :string, allow_nil?: false, public?: true
    attribute :license_version, :string, public?: true
    attribute :license_url, :string, public?: true
    attribute :landing_url, :string, public?: true
    attribute :original_url, :string, public?: true
    attribute :tags, {:array, :string}, default: [], public?: true

    attribute :queries, {:array, :string}, default: [], public?: true
    attribute :uses, :integer, default: 0, allow_nil?: false, public?: true

    timestamps()
  end

  identities do
    identity :unique_key, [:key]
    identity :unique_source, [:source, :source_id]
  end
end
