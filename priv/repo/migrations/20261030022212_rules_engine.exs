defmodule Basa.Repo.Migrations.RulesEngine do
  use Ecto.Migration

  def up do
    create table(:rule_set_versions, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :key, :text, null: false
      add :version, :bigint, null: false
      add :graph, :map, null: false
      add :replaced_by_email, :text

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
    end

    create index(:rule_set_versions, [:key, :version], unique: true)

    create table(:rule_sets, primary_key: false) do
      add :key, :text, null: false, primary_key: true
      add :label, :text, null: false
      add :description, :text
      add :severity, :text, null: false, default: "flag"
      add :points, {:array, :text}, null: false, default: []
      add :subjects, {:array, :text}, null: false, default: []
      add :enabled, :boolean, null: false, default: true
      add :graph, :map, null: false
      add :version, :bigint, null: false, default: 1
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
    drop table(:rule_sets)

    drop_if_exists index(:rule_set_versions, [:key, :version])

    drop table(:rule_set_versions)
  end
end
