defmodule Basa.Repo.Migrations.ServicesOff do
  use Ecto.Migration

  def up do
    alter table(:system_settings) do
      add :services_off, {:array, :text}, null: false, default: []
    end
  end

  def down do
    alter table(:system_settings) do
      remove :services_off
    end
  end
end
