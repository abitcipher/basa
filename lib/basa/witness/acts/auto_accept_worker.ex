defmodule Basa.Witness.Acts.AutoAcceptWorker do
  use Oban.Worker, queue: :default, max_attempts: 5

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"transaction_id" => id}}) do
    tx = Basa.Witness.get_transaction!(id, authorize?: false)

    if tx.status in [:returned, :delivered] do
      case Ash.create(Basa.Witness.Act, %{transaction_id: id},
             action: :auto_accept,
             authorize?: false
           ) do
        {:ok, _} -> :ok
        {:error, _} -> {:cancel, :not_due}
      end
    else
      :ok
    end
  end
end
