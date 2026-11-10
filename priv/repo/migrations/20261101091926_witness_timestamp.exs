defmodule Basa.Repo.Migrations.WitnessTimestamp do
  use Ecto.Migration

  def up do
    alter table(:witness_transactions) do
      add :timestamp_token, :binary
      add :timestamped_at, :utc_datetime_usec
    end
  end

  def down do
    alter table(:witness_transactions) do
      remove :timestamped_at
      remove :timestamp_token
    end
  end
end
