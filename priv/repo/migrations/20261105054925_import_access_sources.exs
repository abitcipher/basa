defmodule Basa.Repo.Migrations.ImportAccessSources do
  use Ecto.Migration

  def up do
    create table(:import_agreements, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :version, :bigint, null: false
      add :body, :text, null: false
      add :published_by_email, :text

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
    end

    create unique_index(:import_agreements, [:version],
             name: "import_agreements_unique_version_index"
           )

    create table(:import_access, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :granted_by_email, :text
      add :granted_at, :utc_datetime_usec, null: false
      add :revoked_at, :utc_datetime_usec
      add :accepted_version, :bigint
      add :accepted_hash, :text
      add :accepted_at, :utc_datetime_usec

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :updated_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :user_id,
          references(:users,
            column: :id,
            name: "import_access_user_id_fkey",
            type: :uuid,
            prefix: "public",
            on_delete: :delete_all
          ),
          null: false
    end

    create unique_index(:import_access, [:user_id], name: "import_access_unique_user_index")

    create table(:import_sources, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :name, :text, null: false
      add :sample_urls, {:array, :text}, null: false, default: []
      add :recipe, :map, null: false, default: %{}
      add :browser, :text, null: false, default: "auto"
      add :insecure, :boolean, null: false, default: false

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :updated_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :owner_id,
          references(:users,
            column: :id,
            name: "import_sources_owner_id_fkey",
            type: :uuid,
            prefix: "public",
            on_delete: :delete_all
          ),
          null: false
    end
  end

  def down do
    drop constraint(:import_sources, "import_sources_owner_id_fkey")

    drop table(:import_sources)

    drop constraint(:import_access, "import_access_user_id_fkey")

    drop_if_exists unique_index(:import_access, [:user_id],
                     name: "import_access_unique_user_index"
                   )

    drop table(:import_access)

    drop_if_exists unique_index(:import_agreements, [:version],
                     name: "import_agreements_unique_version_index"
                   )

    drop table(:import_agreements)
  end
end
