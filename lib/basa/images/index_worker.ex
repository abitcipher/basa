defmodule Basa.Images.IndexWorker do
  use Oban.Worker, queue: :default, max_attempts: 5, unique: [period: 10, keys: [:image_id]]

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"image_id" => id}}) do
    if Basa.Search.enabled?() do
      case Ash.get(Basa.Images.StockImage, id, authorize?: false) do
        {:ok, image} -> Basa.Images.Index.put([image])
        {:error, _} -> Basa.Images.Index.delete(id) && :ok
      end
    else
      :ok
    end
  end

  def enqueue(id) do
    {:ok, _} = Oban.insert(new(%{image_id: id}))
    :ok
  end
end
