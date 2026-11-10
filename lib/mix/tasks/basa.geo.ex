defmodule Mix.Tasks.Basa.Geo.Export do
  @shortdoc "Backs up the geo reference (cities, demand) to a gzipped JSON lines file"
  use Mix.Task
  @requirements ["app.start"]

  @impl true
  def run(args) do
    path = List.first(args) || Basa.Release.default_geo_backup()
    {:ok, counts} = Basa.Geo.Library.export(path)
    Mix.shell().info("#{path}: #{counts.cities} cities, #{counts.demand} demand rows")
  end
end

defmodule Mix.Tasks.Basa.Geo.Import do
  @shortdoc "Loads the geo seed (--seed) or restores a backup file"
  use Mix.Task
  @requirements ["app.start"]

  @impl true
  def run(["--seed"]) do
    Mix.shell().info("#{Basa.Geo.Library.import_seed()} cities loaded from the seed")
  end

  def run([path]) do
    {:ok, counts} = Basa.Geo.Library.restore(path)
    Mix.shell().info("Restored #{counts.cities} cities, #{counts.demand} demand rows")
  end

  def run(_), do: Mix.raise("usage: mix basa.geo.import --seed | <backup path>")
end

defmodule Mix.Tasks.Basa.Geo.Reindex do
  @shortdoc "Rebuilds the Meilisearch city index from Postgres"
  use Mix.Task
  @requirements ["app.start"]

  @impl true
  def run(_args) do
    n = Basa.Geo.Index.reindex_all()
    Basa.Geo.Index.wait_idle(60_000)
    Mix.shell().info("#{n} cities indexed")
  end
end
