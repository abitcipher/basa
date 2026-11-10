defmodule Basa.Repo.Migrations.CatalogSales do
  use Ecto.Migration

  def up do
    alter table(:items) do
      add :sold_at, :utc_datetime_usec
    end

    alter table(:lots) do
      add :deal, :text, null: false, default: "lease"
    end
  end

  def down do
    alter table(:lots) do
      remove :deal
    end

    alter table(:items) do
      remove :sold_at
    end
  end
end
