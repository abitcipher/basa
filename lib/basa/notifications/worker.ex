defmodule Basa.Notifications.Worker do
  use Oban.Worker, queue: :notifications, max_attempts: 5

  alias Basa.Notifications.Text

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"booking_id" => id, "event" => event}}) do
    event = String.to_existing_atom(event)

    booking =
      Ash.get!(Basa.Bookings.Booking, id, load: [lot: [:owner], lessee: []], authorize?: false)

    for user_id <- Basa.Notifications.recipients(booking, event),
        user = user_for(booking, user_id),
        user.telegram_id do
      Basa.Telegram.send_message(user.telegram_id, Text.booking(booking, event, user.locale))
    end

    :ok
  end

  defp user_for(%{lessee: %{id: id} = lessee}, id), do: lessee
  defp user_for(%{lot: %{owner: owner}}, _), do: owner
end
