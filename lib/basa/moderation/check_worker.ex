defmodule Basa.Moderation.CheckWorker do
  use Oban.Worker,
    queue: :moderation,
    max_attempts: 20,
    unique: [period: 300, keys: [:key], states: [:available, :scheduled, :executing]]

  require Ash.Query

  alias Basa.Moderation
  alias Basa.Moderation.PhotoCheck

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"key" => key}}) do
    with true <- Moderation.enabled?() || :off,
         %PhotoCheck{} = check <- find(key) || :gone,
         {:ok, bytes, _type} <- Basa.Storage.get(key) |> stored(),
         {:ok, scores} <- Moderation.check(bytes) do
      record(check, scores)
    else
      :off -> :ok
      :gone -> :ok
      {:error, :missing} -> fail(key, "the photo is no longer stored")
      {:error, {:checker, "unreadable image" <> _ = reason}} -> fail(key, reason)
      {:error, reason} -> {:snooze, if(reason == :not_ready, do: 15, else: 60)}
    end
  end

  defp find(key) do
    PhotoCheck |> Ash.Query.filter(key == ^key) |> Ash.read_one!(authorize?: false)
  end

  defp stored({:ok, bytes, type}), do: {:ok, bytes, type}
  defp stored(_), do: {:error, :missing}

  defp record(check, scores) do
    {verdict, reasons} =
      case Basa.Rules.review_photo(scores) do
        :ok -> {:ok, []}
        {verdict, reasons} -> {verdict, reasons}
      end

    check
    |> Ash.Changeset.for_update(:record, %{
      scores: Map.take(scores, ["nsfw", "detectors", "clip", "ms"]),
      verdict: verdict,
      reasons: reasons,
      level: scores["level"],
      models: scores["models"] || []
    })
    |> Ash.update!(authorize?: false)

    :ok
  end

  defp fail(key, reason) do
    case find(key) do
      nil ->
        :ok

      check ->
        check
        |> Ash.Changeset.for_update(:fail, %{error: reason})
        |> Ash.update!(authorize?: false)
    end

    :ok
  end
end
