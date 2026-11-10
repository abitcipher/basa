defmodule Basa.Repo.Migrations.PhotoChecks do
  use Ecto.Migration

  def up do
    alter table(:system_settings) do
      add :moderation_level, :bigint, null: false, default: 1
    end

    create table(:photo_checks, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :key, :text, null: false
      add :status, :text, null: false, default: "pending"
      add :verdict, :text
      add :reasons, {:array, :text}, default: []
      add :scores, :map
      add :level, :bigint
      add :models, {:array, :text}, default: []
      add :error, :text
      add :checked_at, :utc_datetime_usec
      add :review, :text
      add :reviewed_at, :utc_datetime_usec
      add :updated_by_email, :text

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :updated_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :owner_id,
          references(:users,
            column: :id,
            name: "photo_checks_owner_id_fkey",
            type: :uuid,
            prefix: "public",
            on_delete: :nilify_all
          )
    end

    create unique_index(:photo_checks, [:key], name: "photo_checks_unique_key_index")

    create index(:photo_checks, [:verdict, :review])
  end

  def down do
    drop_if_exists index(:photo_checks, [:verdict, :review])

    drop constraint(:photo_checks, "photo_checks_owner_id_fkey")

    drop_if_exists unique_index(:photo_checks, [:key], name: "photo_checks_unique_key_index")

    drop table(:photo_checks)

    alter table(:system_settings) do
      remove :moderation_level
    end
  end
end
