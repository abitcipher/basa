defmodule Basa.Repo.Migrations.QesQualification do
  use Ecto.Migration

  def up do
    alter table(:witness_qualified_signatures) do
      add :qualification, :text, null: false, default: "unchecked"
      add :qualification_level, :text
      add :qualification_indication, :text
      add :qualification_report, :map
      add :qualification_checked_at, :utc_datetime_usec
    end
  end

  def down do
    alter table(:witness_qualified_signatures) do
      remove :qualification_checked_at
      remove :qualification_report
      remove :qualification_indication
      remove :qualification_level
      remove :qualification
    end
  end
end
