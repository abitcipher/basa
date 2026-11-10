defmodule Basa.Witness.TimestampWorker do
  use Oban.Worker, queue: :default, max_attempts: 20, unique: [period: 300]

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"transaction_id" => id}}) do
    tx = Basa.Witness.get_transaction!(id, authorize?: false)

    cond do
      tx.timestamp_token ->
        :ok

      is_nil(tx.basa_hash) or tx.status in [:draft, :signing, :cancelled] ->
        {:cancel, :not_sealed}

      not Basa.Witness.Timestamp.enabled?() ->
        {:cancel, :switched_off}

      true ->
        with {:ok, %{token: token, time: time}} <- Basa.Witness.Timestamp.stamp(tx.basa_hash) do
          Ash.update!(tx, %{timestamp_token: token, timestamped_at: time},
            action: :record_timestamp,
            authorize?: false
          )

          :ok
        end
    end
  end
end
