defmodule Basa.Repo.Migrations.RoomEntrancePhotos do
  use Ecto.Migration

  def up do
    alter table(:rooms) do
      add :entrance_photos, {:array, :text}, default: []
    end
  end

  def down do
    alter table(:rooms) do
      remove :entrance_photos
    end
  end
end
