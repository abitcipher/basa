defmodule Basa.Notifications do
  def booking_event(booking, event) do
    for user_id <- recipients(booking, event) do
      Basa.Events.notify_user(user_id, {:booking_event, event, booking.id})
    end

    %{booking_id: booking.id, event: to_string(event)}
    |> Basa.Notifications.Worker.new()
    |> Oban.insert()

    :ok
  end

  def recipients(booking, :created), do: [booking.owner_id]
  def recipients(booking, :cancelled), do: [booking.owner_id, booking.lessee_id]
  def recipients(booking, _), do: [booking.lessee_id]
end
