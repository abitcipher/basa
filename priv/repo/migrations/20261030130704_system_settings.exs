defmodule Basa.Repo.Migrations.SystemSettings do
  use Ecto.Migration

  def up do
    create table(:system_settings, primary_key: false) do
      add :id, :text, null: false, default: "global", primary_key: true
      add :widgets_enabled, :boolean, null: false
      add :updated_by_email, :text

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :updated_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
    end
  end

  def down do
    drop table(:system_settings)
  end
end
