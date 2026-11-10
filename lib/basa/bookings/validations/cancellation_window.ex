defmodule Basa.Bookings.Validations.CancellationWindow do
  use Ash.Resource.Validation

  @impl true
  def validate(changeset, _opts, context) do
    booking = changeset.data

    cond do
      context.actor && context.actor.id == booking.owner_id ->
        :ok

      true ->
        lot = Ash.get!(Basa.Catalog.Lot, booking.lot_id, authorize?: false)
        deadline = DateTime.add(booking.starts_at, -lot.cancellation_hours * 3600, :second)

        if DateTime.compare(DateTime.utc_now(), deadline) == :lt,
          do: :ok,
          else:
            {:error,
             field: :status,
             message:
               Basa.I18n.t("can no longer be cancelled (%{hours} h rule)",
                 hours: lot.cancellation_hours
               )}
    end
  end
end
