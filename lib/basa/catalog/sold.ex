defmodule Basa.Catalog.Sold do
  require Ash.Query

  alias Basa.Catalog.Lot

  def mark(booking_id) do
    booking =
      Ash.get!(Basa.Bookings.Booking, booking_id,
        load: [lot: [basket: :items]],
        authorize?: false
      )

    items = booking.lot.basket.items
    now = DateTime.utc_now()

    for item <- items, is_nil(item.sold_at) do
      Ash.update!(item, %{sold_at: now}, action: :mark_sold, authorize?: false)
    end

    item_ids = Enum.map(items, & &1.id)

    Lot
    |> Ash.Query.filter(state != :archived and exists(basket.items, id in ^item_ids))
    |> Ash.read!(authorize?: false)
    |> Enum.each(&Ash.update!(&1, %{}, action: :archive, authorize?: false))

    :ok
  end
end
