defmodule Basa.Import.RefreshWorker do
  use Oban.Worker, queue: :import, max_attempts: 1

  require Ash.Query

  @impl Oban.Worker
  def perform(_job) do
    refresh = if Date.day_of_week(Date.utc_today()) == 1, do: [:daily, :weekly], else: [:daily]

    Basa.Import.Source
    |> Ash.Query.filter(refresh in ^refresh)
    |> Ash.read!(authorize?: false)
    |> Enum.map(&Basa.Import.CrawlWorker.new(%{source_id: &1.id}))
    |> Oban.insert_all()

    :ok
  end
end
