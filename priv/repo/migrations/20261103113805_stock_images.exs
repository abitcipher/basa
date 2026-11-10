defmodule Basa.Repo.Migrations.StockImages do
  use Ecto.Migration

  def up do
    alter table(:items) do
      add :no_photos, :boolean, null: false, default: false
    end

    create table(:stock_images, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :key, :text, null: false
      add :sha256, :text, null: false
      add :content_type, :text, null: false
      add :byte_size, :bigint
      add :width, :bigint
      add :height, :bigint
      add :source, :text, null: false
      add :source_id, :text, null: false
      add :title, :text
      add :creator, :text
      add :creator_url, :text
      add :license, :text, null: false
      add :license_version, :text
      add :license_url, :text
      add :landing_url, :text
      add :original_url, :text
      add :tags, {:array, :text}, default: []
      add :queries, {:array, :text}, default: []
      add :uses, :bigint, null: false, default: 0

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :updated_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
    end

    create unique_index(:stock_images, [:key], name: "stock_images_unique_key_index")

    create unique_index(:stock_images, [:source, :source_id],
             name: "stock_images_unique_source_index"
           )
  end

  def down do
    drop_if_exists unique_index(:stock_images, [:source, :source_id],
                     name: "stock_images_unique_source_index"
                   )

    drop_if_exists unique_index(:stock_images, [:key], name: "stock_images_unique_key_index")

    drop table(:stock_images)

    alter table(:items) do
      remove :no_photos
    end
  end
end
