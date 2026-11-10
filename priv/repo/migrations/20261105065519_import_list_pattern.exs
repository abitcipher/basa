defmodule Basa.Repo.Migrations.ImportListPattern do
  use Ecto.Migration

  def up do
    alter table(:import_sources) do
      add :list_pattern, :text
    end
  end

  def down do
    alter table(:import_sources) do
      remove :list_pattern
    end
  end
end
