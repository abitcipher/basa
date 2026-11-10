defmodule Basa.Events.PublishWorker do
  use Oban.Worker, queue: :events, max_attempts: 20

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"type" => type} = envelope}) do
    Basa.Events.RabbitPublisher.publish(type, Jason.encode!(envelope), id: envelope["id"])
  end

  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}), do: min(5 * Integer.pow(2, attempt), 600)
end
