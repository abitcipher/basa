defmodule Basa.Repo.Migrations.NearMeSettings do
  use Ecto.Migration

  def up do
    alter table(:system_settings) do
      add :near_control, :text, null: false, default: "slider"

      add :near_steps_km, {:array, :bigint},
        null: false,
        default: fragment("ARRAY[1, 10, 25, 75, 125]")

      add :near_city, :boolean, null: false, default: true
      add :near_region, :boolean, null: false, default: true
      add :near_default, :text, null: false, default: "25"
    end
  end

  def down do
    alter table(:system_settings) do
      remove :near_default
      remove :near_region
      remove :near_city
      remove :near_steps_km
      remove :near_control
    end
  end
end
