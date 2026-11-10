defmodule Basa.Import.Source do
  use Ash.Resource,
    otp_app: :basa,
    domain: Basa.Import,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshJsonApi.Resource]

  json_api do
    type "import_source"
  end

  postgres do
    table "import_sources"
    repo Basa.Repo

    references do
      reference :owner, on_delete: :delete
    end
  end

  @max_samples 5

  actions do
    defaults [:read, :destroy]

    read :mine do
      filter expr(owner_id == ^actor(:id))
      prepare build(sort: [inserted_at: :desc])
    end

    action :crawl, :map do
      argument :id, :uuid, allow_nil?: false
      run Basa.Import.Actions.Crawl
    end

    action :import_page, :map do
      argument :id, :uuid, allow_nil?: false
      argument :url, :string, allow_nil?: false
      run Basa.Import.Actions.ImportPage
    end

    create :create do
      primary? true
      accept [:name, :sample_urls, :browser]
      change relate_actor(:owner)
    end

    update :update do
      primary? true
      require_atomic? false

      accept [
        :name,
        :sample_urls,
        :browser,
        :recipe,
        :category_map,
        :default_category_id,
        :catalogue_urls,
        :link_pattern,
        :list_pattern,
        :next_selector,
        :use_sitemap,
        :max_pages,
        :max_items,
        :refresh
      ]
    end

    update :crawled do
      require_atomic? false
      accept [:last_crawl_at, :last_crawl_found, :last_crawl_error]
    end

    update :set_insecure do
      require_atomic? false
      accept [:insecure]
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if actor_attribute_equals(:role, :admin)
      authorize_if relates_to_actor_via(:owner)
    end

    policy action(:create) do
      authorize_if Basa.Import.Checks.HasAccess
    end

    policy action([:update, :destroy]) do
      forbid_unless Basa.Import.Checks.HasAccess
      authorize_if relates_to_actor_via(:owner)
    end

    policy action(:crawled) do
      forbid_unless Basa.Import.Checks.HasAccess
      authorize_if relates_to_actor_via(:owner)
    end

    policy action([:crawl, :import_page]) do
      authorize_if Basa.Import.Checks.HasAccess
    end

    policy action(:set_insecure) do
      authorize_if actor_attribute_equals(:role, :admin)
    end
  end

  validations do
    validate string_length(:name, min: 1, max: 120)

    validate fn changeset, _ ->
      urls = Ash.Changeset.get_attribute(changeset, :catalogue_urls) || []
      pattern = Ash.Changeset.get_attribute(changeset, :link_pattern)

      cond do
        length(urls) > 10 ->
          {:error, field: :catalogue_urls, message: "at most 10 pages"}

        not Enum.all?(urls, &web_url?/1) ->
          {:error, field: :catalogue_urls, message: "must be http or https addresses"}

        not Basa.Import.Crawl.valid_pattern?(pattern) ->
          {:error, field: :link_pattern, message: "is not a valid pattern"}

        not Basa.Import.Crawl.valid_pattern?(
          Ash.Changeset.get_attribute(changeset, :list_pattern)
        ) ->
          {:error, field: :list_pattern, message: "is not a valid pattern"}

        true ->
          :ok
      end
    end

    validate numericality(:max_pages, greater_than_or_equal_to: 1, less_than_or_equal_to: 100)
    validate numericality(:max_items, greater_than_or_equal_to: 1, less_than_or_equal_to: 2000)

    validate fn changeset, _ ->
      urls = Ash.Changeset.get_attribute(changeset, :sample_urls) || []

      cond do
        urls == [] ->
          {:error, field: :sample_urls, message: "add at least one page"}

        length(urls) > @max_samples ->
          {:error, field: :sample_urls, message: "at most #{@max_samples} pages"}

        Enum.all?(urls, &web_url?/1) ->
          :ok

        true ->
          {:error, field: :sample_urls, message: "must be http or https addresses"}
      end
    end
  end

  defp web_url?(url) do
    uri = URI.parse(url)
    uri.scheme in ["http", "https"] and uri.host not in [nil, ""]
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false, public?: true, constraints: [trim?: true]
    attribute :sample_urls, {:array, :string}, allow_nil?: false, default: [], public?: true
    attribute :recipe, :map, allow_nil?: false, default: %{}, public?: true

    attribute :browser, :atom,
      allow_nil?: false,
      default: :auto,
      public?: true,
      constraints: [one_of: [:auto, :always, :never]]

    attribute :insecure, :boolean, allow_nil?: false, default: false, public?: true

    attribute :category_map, :map, allow_nil?: false, default: %{}, public?: true

    attribute :catalogue_urls, {:array, :string}, allow_nil?: false, default: [], public?: true
    attribute :link_pattern, :string, public?: true
    attribute :list_pattern, :string, public?: true
    attribute :next_selector, :string, public?: true
    attribute :use_sitemap, :boolean, allow_nil?: false, default: false, public?: true
    attribute :max_pages, :integer, allow_nil?: false, default: 20, public?: true
    attribute :max_items, :integer, allow_nil?: false, default: 200, public?: true

    attribute :refresh, :atom,
      allow_nil?: false,
      default: :off,
      public?: true,
      constraints: [one_of: [:off, :daily, :weekly]]

    attribute :last_crawl_at, :utc_datetime_usec, public?: true
    attribute :last_crawl_found, :integer, public?: true
    attribute :last_crawl_error, :string, public?: true
    timestamps()
  end

  relationships do
    belongs_to :owner, Basa.Accounts.User, allow_nil?: false
    belongs_to :default_category, Basa.Catalog.Category, public?: true
    has_many :entries, Basa.Import.Entry
  end
end
