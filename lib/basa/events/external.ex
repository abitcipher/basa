defmodule Basa.Events.External do
  require Logger

  def publish(type, data) do
    envelope = %{
      "id" => Ecto.UUID.generate(),
      "type" => type,
      "occurred_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "data" => data
    }

    case Application.get_env(:basa, :external_publisher) do
      nil ->
        Logger.debug("event #{type} #{inspect(data)}")
        :ok

      _publisher ->
        envelope |> Basa.Events.PublishWorker.new() |> Oban.insert()
        :ok
    end
  end

  def booking_data(b) do
    %{
      booking_id: b.id,
      lot_id: b.lot_id,
      owner_id: b.owner_id,
      lessee_id: b.lessee_id,
      status: b.status,
      starts_at: b.starts_at,
      ends_at: b.ends_at,
      units: b.units,
      price_amount: b.price_amount && Decimal.to_string(b.price_amount),
      currency: b.currency
    }
  end

  def lot_data(l) do
    %{
      lot_id: l.id,
      owner_id: l.owner_id,
      state: l.state,
      title: l.title,
      price_amount: l.price_amount && Decimal.to_string(l.price_amount),
      currency: l.currency,
      price_unit: l.price_unit
    }
  end
end
