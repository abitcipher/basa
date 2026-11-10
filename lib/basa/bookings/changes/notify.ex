defmodule Basa.Bookings.Changes.Notify do
  use Ash.Resource.Change

  @impl true
  def change(changeset, opts, _context) do
    Ash.Changeset.after_transaction(changeset, fn
      _changeset, {:ok, booking} ->
        Basa.Notifications.booking_event(booking, opts[:event])
        {:ok, booking}

      _changeset, error ->
        error
    end)
  end
end
