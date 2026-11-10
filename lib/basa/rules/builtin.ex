defmodule Basa.Rules.Builtin do
  @behaviour Basa.Rules

  @impl true
  def review_lot(lot) do
    reasons =
      []
      |> check(
        lot.basket.items == [] and lot.basket.attendants == [] and is_nil(lot.room),
        "Add at least one item, attendant or a room"
      )
      |> check(String.length(lot.title || "") < 5, "The title is too short")
      |> check(Decimal.compare(lot.price_amount, 0) != :gt, "Set a price above zero")
      |> check(
        lot.room && (is_nil(lot.room.lat) or is_nil(lot.room.lng)),
        "The room needs a location"
      )
      |> check(
        Basa.Moderation.hidden_count(Basa.Rules.Jdm.lot_photos(lot)) > 0,
        "Some photos were hidden after a check: remove or replace them"
      )

    cond do
      reasons != [] -> {:reject, Enum.reverse(reasons)}
      suspicious?(lot) -> :manual
      true -> :approve
    end
  end

  @impl true
  def review_photo(scores) do
    %{"photo" => %{"nsfw" => nsfw, "clip" => clip}} = Basa.Rules.Jdm.photo_facts(scores)

    flags =
      []
      |> check(nsfw >= 0.6, "photo_nudity_possible")
      |> check(
        clip["weapon"] >= 0.5 or clip["drugs"] >= 0.5 or clip["gore"] >= 0.5,
        "photo_harm"
      )
      |> check(
        clip["document"] >= 0.5,
        "photo_documents"
      )
      |> Enum.sort()

    cond do
      nsfw >= 0.9 -> {:block, ["photo_nudity_clear"]}
      flags != [] -> {:flag, flags}
      true -> :ok
    end
  end

  defp check(reasons, true, reason), do: [reason | reasons]
  defp check(reasons, _, _), do: reasons

  defp suspicious?(lot) do
    total =
      Enum.reduce(lot.basket.items, Decimal.new(0), fn item, acc ->
        Decimal.add(acc, item.estimated_value || 0)
      end)

    Decimal.compare(total, 5_000_000) == :gt
  end
end
