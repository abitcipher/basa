defmodule Basa.Repo.Migrations.UserCardGlow do
  use Ecto.Migration

  def up do
    alter table(:users) do
      add :glow, :boolean, null: false, default: true
    end
  end

  def down do
    alter table(:users) do
      remove :glow
    end
  end
end
