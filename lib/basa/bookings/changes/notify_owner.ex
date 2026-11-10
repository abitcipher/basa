defmodule Basa.Bookings.Changes.NotifyOwner do
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_transaction(changeset, fn
      _cs, {:ok, booking} ->
        Basa.Events.bookings_changed(booking.owner_id)
        {:ok, booking}

      _cs, other ->
        other
    end)
  end

  @impl true
  def atomic(changeset, opts, context), do: {:ok, change(changeset, opts, context)}
end
