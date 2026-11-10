defmodule Basa.Repo.Migrations.AddBasaDomainExtensions1 do
  use Ecto.Migration

  def up do
    execute("CREATE EXTENSION IF NOT EXISTS \"btree_gist\"")
    execute("CREATE EXTENSION IF NOT EXISTS \"postgis\"")
  end

  def down do
  end
end
