defmodule Basa.Geo.IndexWorker do
  use Oban.Worker, queue: :default, max_attempts: 5, unique: [period: 10, keys: [:city_id]]

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"city_id" => id}}) do
    with true <- Basa.Search.enabled?(),
         {:ok, city} <- Ash.get(Basa.Geo.City, id, authorize?: false) do
      Basa.Geo.Index.put([city])
    else
      _ -> :ok
    end
  end

  def enqueue(ids) do
    ids |> Enum.uniq() |> Enum.map(&new(%{city_id: &1})) |> Oban.insert_all()
    :ok
  end
end
