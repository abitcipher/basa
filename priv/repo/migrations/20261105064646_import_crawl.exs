defmodule Basa.Repo.Migrations.ImportCrawl do
  use Ecto.Migration

  def up do
    alter table(:import_sources) do
      add :catalogue_urls, {:array, :text}, null: false, default: []
      add :link_pattern, :text
      add :next_selector, :text
      add :use_sitemap, :boolean, null: false, default: false
      add :max_pages, :bigint, null: false, default: 20
      add :max_items, :bigint, null: false, default: 200
      add :refresh, :text, null: false, default: "off"
      add :last_crawl_at, :utc_datetime_usec
      add :last_crawl_found, :bigint
      add :last_crawl_error, :text
    end
  end

  def down do
    alter table(:import_sources) do
      remove :last_crawl_error
      remove :last_crawl_found
      remove :last_crawl_at
      remove :refresh
      remove :max_items
      remove :max_pages
      remove :use_sitemap
      remove :next_selector
      remove :link_pattern
      remove :catalogue_urls
    end
  end
end
