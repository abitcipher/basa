defmodule Basa.Import.CrawlWorker do
  use Oban.Worker, queue: :import, max_attempts: 2, unique: [period: 600, keys: [:source_id]]

  alias Basa.Import
  alias Basa.Import.{Crawl, PageWorker}

  @spacing_s 3

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"source_id" => id}}) do
    with {:ok, source, owner} <- Import.source_with_owner(id),
         true <- Import.enabled?() and Import.allowed?(owner) do
      case Crawl.discover(source) do
        {:ok, %{urls: urls}} ->
          urls
          |> Enum.with_index()
          |> Enum.map(fn {url, i} ->
            PageWorker.new(%{source_id: source.id, url: url}, schedule_in: i * @spacing_s)
          end)
          |> Oban.insert_all()

          crawled(source, owner, length(urls), nil)

        {:error, reason} ->
          crawled(source, owner, 0, inspect(reason))
      end
    else
      _ -> :ok
    end
  end

  defp crawled(source, owner, found, error) do
    {:ok, _} =
      Import.record_crawl(
        source,
        %{last_crawl_at: DateTime.utc_now(), last_crawl_found: found, last_crawl_error: error},
        actor: owner
      )

    :ok
  end
end
