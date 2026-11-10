defmodule Basa.Release do
  @app :basa

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def seed do
    load_app()
    seeds = Application.app_dir(@app, "priv/repo/seeds.exs")
    {:ok, _} = Application.ensure_all_started(:req)

    for repo <- repos() do
      {:ok, _, _} =
        Ecto.Migrator.with_repo(repo, fn _repo ->
          Code.eval_file(seeds)
          Basa.Rules.Library.sync()
          Basa.Geo.Library.import_seed()
        end)
    end
  end

  def geo_export(path \\ default_geo_backup()),
    do: with_app(fn -> Basa.Geo.Library.export(path) end)

  def geo_restore(path), do: with_app(fn -> Basa.Geo.Library.restore(path) end)

  def geo_reindex, do: with_app(fn -> Basa.Geo.Index.reindex_all() end)

  def default_geo_backup do
    stamp = Calendar.strftime(DateTime.utc_now(), "%Y%m%d-%H%M%S")
    Path.join(System.get_env("BACKUP_DIR", "backups"), "geo-#{stamp}.jsonl.gz")
  end

  defp with_app(fun) do
    load_app()
    {:ok, _} = Application.ensure_all_started(@app)
    fun.()
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.ensure_all_started(:ssl)
    Application.ensure_loaded(@app)
  end
end
