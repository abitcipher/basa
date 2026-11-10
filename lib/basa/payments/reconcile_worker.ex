defmodule Basa.Payments.ReconcileWorker do
  use Oban.Worker, queue: :default, max_attempts: 3

  @checks [5, 30, 120, 1440]

  def schedule(payment_id) do
    @checks
    |> Enum.map(&new(%{payment_id: payment_id}, schedule_in: &1 * 60))
    |> Oban.insert_all()
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"payment_id" => id}}) do
    case Ash.get(Basa.Payments.Payment, id, authorize?: false) do
      {:ok, %{status: :pending} = payment} ->
        case Basa.Payments.Settle.refresh(payment) do
          {:ok, _} -> :ok
          {:error, reason} -> {:error, reason}
        end

      _ ->
        :ok
    end
  end
end
