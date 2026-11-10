defmodule Basa.AI.SuggestWorker do
  use Oban.Worker, queue: :ai, max_attempts: 3

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"item_id" => id}}) do
    item = Ash.get!(Basa.Catalog.Item, id, authorize?: false)
    slugs = Basa.Catalog.list_categories!(authorize?: false) |> Enum.map(& &1.slug)

    with [key | _] <- item.photos,
         {:ok, body, type} <- Basa.Storage.get(key),
         {:ok, [best | _] = all} <- Basa.AI.recognize(body, type, category_slugs: slugs) do
      category =
        Enum.find(
          Basa.Catalog.list_categories!(authorize?: false),
          &(&1.slug == best.category_slug)
        )

      placeholder? =
        item.brand == nil and item.model == nil and String.contains?(item.title, "Telegram")

      changes =
        %{
          ai_suggestion: %{
            "suggestions" => Enum.map(all, &Map.new(&1, fn {k, v} -> {to_string(k), v} end))
          }
        }
        |> Map.merge(
          if placeholder?,
            do: %{
              title: best.title,
              brand: best.brand,
              model: best.model,
              category_id: category && category.id
            },
            else: %{}
        )

      item
      |> Ash.Changeset.for_update(:update, changes, authorize?: false)
      |> Ash.update!(authorize?: false)

      :ok
    else
      {:error, :disabled} -> {:cancel, :ai_disabled}
      {:error, reason} -> {:error, reason}
      _ -> :ok
    end
  end
end
