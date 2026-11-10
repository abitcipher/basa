defmodule Basa.Import.Actions.ImportPage do
  use Ash.Resource.Actions.Implementation

  alias Basa.Import.Actions.Shared

  @impl true
  def run(input, _opts, context) do
    url = String.trim(input.arguments.url)

    with {:ok, source} <- Shared.own_source(input.arguments.id, context.actor),
         :ok <- Shared.import_on(),
         :ok <- web_url(url),
         {:ok, _job} <- Oban.insert(Basa.Import.PageWorker.new(%{source_id: source.id, url: url})) do
      {:ok, %{"queued" => true, "source_id" => source.id, "url" => url}}
    end
  end

  defp web_url(url) do
    uri = URI.parse(url)

    if uri.scheme in ["http", "https"] and uri.host not in [nil, ""],
      do: :ok,
      else: Shared.invalid(:url, "must be an http or https address")
  end
end
