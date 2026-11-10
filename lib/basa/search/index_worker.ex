defmodule Basa.Search.IndexWorker do
  use Oban.Worker, queue: :default, max_attempts: 5, unique: [period: 5, keys: [:lot_id]]

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"lot_id" => lot_id}}) do
    if Basa.Search.enabled?() do
      case Basa.Search.index_lot(lot_id) do
        {:ok, %{status: s}} when s in 200..299 -> :ok
        {:ok, resp} -> {:error, {:http, resp.status}}
        {:error, reason} -> {:error, reason}
      end
    else
      :ok
    end
  end

  def enqueue(lot_ids) do
    lot_ids
    |> Enum.uniq()
    |> Enum.map(&new(%{lot_id: &1}))
    |> Oban.insert_all()

    :ok
  end
end
