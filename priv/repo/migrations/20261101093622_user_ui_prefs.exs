defmodule Basa.Repo.Migrations.UserUiPrefs do
  use Ecto.Migration

  def up do
    alter table(:users) do
      add :ui, :map, null: false, default: %{}
    end
  end

  def down do
    alter table(:users) do
      remove :ui
    end
  end
end
