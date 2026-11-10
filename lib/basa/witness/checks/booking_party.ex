defmodule Basa.Witness.Checks.BookingParty do
  use Ash.Policy.SimpleCheck

  @impl true
  def describe(_), do: "actor is the booking's lessor or lessee"

  @impl true
  def match?(nil, _context, _opts), do: false

  def match?(actor, %{changeset: %Ash.Changeset{} = changeset}, _opts) do
    with id when is_binary(id) <- Ash.Changeset.get_argument(changeset, :booking_id),
         {:ok, booking} <-
           Ash.get(Basa.Bookings.Booking, id, load: [lot: [:owner_id]], authorize?: false) do
      actor.id in [booking.lessee_id, booking.lot.owner_id]
    else
      _ -> false
    end
  end

  def match?(_, _, _), do: false
end
