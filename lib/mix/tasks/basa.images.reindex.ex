defmodule Mix.Tasks.Basa.Images.Reindex do
  @shortdoc "Rebuilds the Meilisearch index of cached pictures"
  use Mix.Task

  @impl true
  def run(_args) do
    Mix.Task.run("app.start")
    n = Basa.Images.Index.reindex_all()
    Basa.Search.wait_idle(60_000, Basa.Images.Index.index_name())
    Mix.shell().info("Reindexed #{n} pictures into #{Basa.Images.Index.index_name()}")
  end
end
