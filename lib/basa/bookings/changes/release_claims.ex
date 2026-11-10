defmodule Basa.Bookings.Changes.ReleaseClaims do
  use Ash.Resource.Change
  require Ash.Query

  @impl true
  def change(changeset, _opts, _context) do
    changeset
    |> Ash.Changeset.after_action(fn _changeset, booking ->
      Basa.Bookings.Claim
      |> Ash.Query.filter(booking_id == ^booking.id and active == true)
      |> Ash.bulk_update!(:release, %{}, authorize?: false, strategy: [:atomic, :stream])

      {:ok, booking}
    end)
    |> Ash.Changeset.after_transaction(fn
      _changeset, {:ok, booking} ->
        Basa.Events.availability_changed(booking.owner_id)
        {:ok, booking}

      _changeset, error ->
        error
    end)
  end
end
