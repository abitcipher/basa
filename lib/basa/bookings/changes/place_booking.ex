defmodule Basa.Bookings.Changes.PlaceBooking do
  use Ash.Resource.Change

  require Ash.Query

  alias Basa.Bookings.{Claim, Schedule}

  @impl true
  def change(changeset, _opts, context) do
    changeset
    |> Ash.Changeset.before_action(&prepare(&1, context.actor))
    |> Ash.Changeset.after_action(&claim_resources/2)
    |> Ash.Changeset.after_transaction(fn
      _changeset, {:ok, booking} ->
        Basa.Events.availability_changed(booking.owner_id)
        Basa.Notifications.booking_event(booking, :created)
        {:ok, booking}

      _changeset, error ->
        error
    end)
  end

  defp prepare(changeset, actor) do
    lot_id = Ash.Changeset.get_attribute(changeset, :lot_id)
    starts_at = Ash.Changeset.get_attribute(changeset, :starts_at)
    ends_at = Ash.Changeset.get_attribute(changeset, :ends_at)

    with {:ok, lot} <- load_lot(lot_id),
         :ok <- not_own(lot, actor),
         :ok <- not_reserved(lot),
         {:ok, %{units: units, price: price}} <- quote(lot, starts_at, ends_at) do
      changeset
      |> Ash.Changeset.force_change_attributes(%{
        owner_id: lot.owner_id,
        units: units,
        price_amount: price,
        currency: lot.currency,
        status: if(lot.booking_mode == :instant, do: :confirmed, else: :pending)
      })
      |> Ash.Changeset.put_context(:lot, lot)
    else
      {:error, field, message} ->
        Ash.Changeset.add_error(changeset, field: field, message: message)
    end
  end

  defp load_lot(nil), do: {:error, :lot_id, Basa.I18n.t("is required")}

  defp load_lot(id) do
    case Ash.get(Basa.Catalog.Lot, id, load: [basket: [:items, :attendants]], authorize?: false) do
      {:ok, %{state: :published} = lot} -> {:ok, lot}
      _ -> {:error, :lot_id, Basa.I18n.t("is not available for booking")}
    end
  end

  defp not_own(%{owner_id: id}, %{id: id}),
    do: {:error, :lot_id, Basa.I18n.t("is your own offer")}

  defp not_own(_, _), do: :ok

  defp not_reserved(%{deal: :sale, id: id}) do
    reserved? =
      Basa.Bookings.Booking
      |> Ash.Query.filter(lot_id == ^id and status in [:pending, :confirmed, :completed])
      |> Ash.exists?(authorize?: false)

    if reserved?, do: {:error, :lot_id, Basa.I18n.t("is already reserved by a buyer")}, else: :ok
  end

  defp not_reserved(_lot), do: :ok

  defp quote(_lot, nil, _), do: {:error, :starts_at, Basa.I18n.t("is required")}
  defp quote(_lot, _, nil), do: {:error, :ends_at, Basa.I18n.t("is required")}
  defp quote(lot, s, e), do: Schedule.quote(lot, s, e)

  defp claim_resources(changeset, booking) do
    lot = changeset.context.lot
    blocked_until = DateTime.add(booking.ends_at, lot.buffer_minutes * 60, :second)

    resources =
      [{:room, lot.room_id}] ++
        Enum.map(lot.basket.items, &{:item, &1.id}) ++
        Enum.map(lot.basket.attendants, &{:attendant, &1.id})

    Enum.reduce_while(resources, {:ok, booking}, fn {type, id}, ok ->
      Claim
      |> Ash.Changeset.for_create(:create, %{
        booking_id: booking.id,
        owner_id: booking.owner_id,
        resource_type: type,
        resource_id: id,
        starts_at: booking.starts_at,
        ends_at: blocked_until
      })
      |> Ash.create(authorize?: false)
      |> case do
        {:ok, _claim} -> {:cont, ok}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end
end
