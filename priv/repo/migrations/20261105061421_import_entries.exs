defmodule Basa.Repo.Migrations.ImportEntries do
  use Ecto.Migration

  def up do
    create table(:import_entries, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :url, :text, null: false
      add :status, :text, null: false
      add :error, :text
      add :fingerprint, :text
      add :imported_at, :utc_datetime_usec, null: false

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :updated_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :source_id,
          references(:import_sources,
            column: :id,
            name: "import_entries_source_id_fkey",
            type: :uuid,
            prefix: "public",
            on_delete: :delete_all
          ),
          null: false
    end

    create unique_index(:import_entries, [:source_id, :url],
             name: "import_entries_unique_url_index"
           )

    alter table(:import_entries) do
      add :item_id,
          references(:items,
            column: :id,
            name: "import_entries_item_id_fkey",
            type: :uuid,
            prefix: "public",
            on_delete: :nilify_all
          )
    end

    alter table(:import_sources) do
      add :category_map, :map, null: false, default: %{}

      add :default_category_id,
          references(:categories,
            column: :id,
            name: "import_sources_default_category_id_fkey",
            type: :uuid,
            prefix: "public"
          )
    end
  end

  def down do
    drop constraint(:import_sources, "import_sources_default_category_id_fkey")

    alter table(:import_sources) do
      remove :default_category_id
      remove :category_map
    end

    drop constraint(:import_entries, "import_entries_item_id_fkey")

    drop constraint(:import_entries, "import_entries_source_id_fkey")

    alter table(:import_entries) do
      remove :item_id
    end

    drop_if_exists unique_index(:import_entries, [:source_id, :url],
                     name: "import_entries_unique_url_index"
                   )

    drop table(:import_entries)
  end
end
