defmodule Basa.Import.PageWorker do
  use Oban.Worker,
    queue: :import,
    max_attempts: 3,
    unique: [period: 3600, keys: [:source_id, :url]]

  alias Basa.Import

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"source_id" => id, "url" => url}}) do
    with {:ok, source, owner} <- Import.source_with_owner(id),
         true <- Import.enabled?() and Import.allowed?(owner) do
      Import.import_page(source, url, owner)
      :ok
    else
      _ -> :ok
    end
  end
end
