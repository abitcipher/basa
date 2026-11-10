defmodule Basa.Rules.Jdm do
  @behaviour Basa.Rules

  alias Basa.Rules.Check

  @impl true
  def review_lot(lot) do
    violations = Check.run("lot.submit", "lot", facts(lot))

    cond do
      Check.any?(violations, :block) ->
        {:reject,
         violations
         |> Enum.filter(&(&1.rule.severity == :block))
         |> Enum.map(&message/1)
         |> Enum.uniq()}

      Check.any?(violations, :flag) ->
        :manual

      true ->
        :approve
    end
  end

  @impl true
  def review_photo(scores) do
    violations = Check.run("photo.check", "photo", photo_facts(scores))

    reasons = fn severity ->
      violations
      |> Enum.filter(&(&1.rule.severity == severity))
      |> Enum.map(&(&1.code || &1.rule.key))
      |> Enum.uniq()
      |> Enum.sort()
    end

    cond do
      Check.any?(violations, :block) -> {:block, reasons.(:block)}
      Check.any?(violations, :flag) -> {:flag, reasons.(:flag)}
      true -> :ok
    end
  end

  def photo_facts(scores) do
    clip =
      Map.merge(
        Map.new(Basa.Moderation.Phrases.keys(), &{&1, 0.0}),
        scores["clip"] || %{}
      )

    %{
      "point" => "photo.check",
      "subject" => "photo",
      "photo" => %{"nsfw" => scores["nsfw"] || 0.0, "level" => scores["level"], "clip" => clip}
    }
  end

  def facts(lot) do
    items = lot.basket.items

    total =
      Enum.reduce(items, Decimal.new(0), fn item, acc ->
        Decimal.add(acc, item.estimated_value || 0)
      end)

    %{
      "point" => "lot.submit",
      "subject" => "lot",
      "lot" => %{
        "title" => lot.title,
        "titleLength" => String.length(lot.title || ""),
        "priceAmount" => Decimal.to_float(lot.price_amount || Decimal.new(0)),
        "currency" => to_string(lot.currency),
        "priceUnit" => to_string(lot.price_unit),
        "itemCount" => length(items),
        "attendantCount" => length(lot.basket.attendants),
        "totalValue" => Decimal.to_float(total),
        "hasRoom" => not is_nil(lot.room),
        "roomHasLocation" =>
          not is_nil(lot.room) and not is_nil(lot.room.lat) and not is_nil(lot.room.lng),
        "city" => lot.room && lot.room.city,
        "mobile" => (lot.room && lot.room.mobile) || false,
        "photosHidden" => Basa.Moderation.hidden_count(lot_photos(lot))
      }
    }
  end

  def lot_photos(lot) do
    Enum.flat_map(lot.basket.items, &(&1.photos || [])) ++
      if(lot.room, do: (lot.room.photos || []) ++ (lot.room.entrance_photos || []), else: [])
  end

  defp message(%{code: code, message: message}) do
    translated = code && Basa.I18n.t(code)
    if translated && translated != code, do: translated, else: message || code
  end
end
