defmodule Basa.Import.Actions.Crawl do
  use Ash.Resource.Actions.Implementation

  alias Basa.Import
  alias Basa.Import.Actions.Shared

  @impl true
  def run(input, _opts, context) do
    actor = context.actor

    with {:ok, source} <- Shared.own_source(input.arguments.id, actor),
         :ok <- Shared.import_on(),
         :ok <- Import.crawl_now(source, actor) do
      {:ok, %{"queued" => true, "source_id" => source.id}}
    else
      {:error, :forbidden} -> {:error, Ash.Error.Forbidden.exception([])}
      error -> error
    end
  end
end
