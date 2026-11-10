defmodule Basa.Repo.Migrations.QesProviderData do
  use Ecto.Migration

  def up do
    alter table(:witness_qualified_signatures) do
      add :provider_data, :map, null: false, default: %{}
    end
  end

  def down do
    alter table(:witness_qualified_signatures) do
      remove :provider_data
    end
  end
end
