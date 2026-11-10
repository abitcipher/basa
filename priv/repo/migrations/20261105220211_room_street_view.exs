defmodule Basa.Repo.Migrations.RoomStreetView do
  use Ecto.Migration

  def up do
    alter table(:rooms) do
      add :street_view, :map
    end
  end

  def down do
    alter table(:rooms) do
      remove :street_view
    end
  end
end
