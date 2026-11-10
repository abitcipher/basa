defmodule Mix.Tasks.Basa.Search.Reindex do
  @shortdoc "Rebuilds the Meilisearch index of published lots"
  use Mix.Task

  @impl true
  def run(_args) do
    Mix.Task.run("app.start")
    Basa.Search.reindex_all()
    Basa.Search.wait_idle(60_000)
    Mix.shell().info("Reindexed published lots into #{Basa.Search.index_name()}")
  end
end
