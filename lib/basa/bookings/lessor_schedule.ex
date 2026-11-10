defmodule Basa.Bookings.LessorSchedule do
  require Ash.Query
  alias Basa.Bookings.{Booking, Claim}

  @shown [:pending, :confirmed, :completed]

  def bookings(owner, %Date{} = from, %Date{} = to) do
    {starts, ends} = bounds(from, to)

    Booking
    |> Ash.Query.filter(
      owner_id == ^owner.id and status in ^@shown and starts_at < ^ends and ends_at > ^starts
    )
    |> Ash.Query.sort(starts_at: :asc)
    |> Ash.Query.load([:lessee, lot: [:room]])
    |> Ash.read!(authorize?: false)
    |> Enum.map(&booking_row/1)
  end

  def resources(owner, %Date{} = from, %Date{} = to) do
    {starts, ends} = bounds(from, to)

    claims =
      Claim
      |> Ash.Query.filter(
        owner_id == ^owner.id and active == true and starts_at < ^ends and ends_at > ^starts
      )
      |> Ash.Query.sort(starts_at: :asc)
      |> Ash.Query.load(booking: [:lessee, :lot])
      |> Ash.read!(authorize?: false)
      |> Enum.filter(&(&1.booking.status in @shown))
      |> Enum.group_by(&{&1.resource_type, &1.resource_id})

    rooms = owned(Basa.Catalog.Room, owner) |> Enum.map(&{:room, &1.id, &1.title})
    items = owned(Basa.Catalog.Item, owner) |> Enum.map(&{:item, &1.id, &1.title})
    people = owned(Basa.Catalog.Attendant, owner) |> Enum.map(&{:attendant, &1.id, &1.name})

    for {type, id, title} <- rooms ++ items ++ people do
      %{
        id: id,
        type: type,
        title: title,
        bookings:
          for c <- Map.get(claims, {type, id}, []) do
            %{
              booking_id: c.booking_id,
              starts_at: c.starts_at,
              ends_at: c.ends_at,
              status: c.booking.status,
              lot_title: c.booking.lot.title,
              lessee: lessee_name(c.booking.lessee)
            }
          end
      }
    end
  end

  defp booking_row(b) do
    %{
      id: b.id,
      lot_id: b.lot_id,
      lot_title: b.lot.title,
      room_title: b.lot.room && b.lot.room.title,
      starts_at: b.starts_at,
      ends_at: b.ends_at,
      status: b.status,
      lessee: lessee_name(b.lessee),
      timezone: b.lot.timezone,
      price_amount: b.price_amount,
      currency: b.currency
    }
  end

  defp owned(resource, owner) do
    resource
    |> Ash.Query.filter(owner_id == ^owner.id)
    |> Ash.Query.sort(inserted_at: :asc)
    |> Ash.read!(authorize?: false)
  end

  defp bounds(from, to) do
    {DateTime.new!(Date.add(from, -1), ~T[00:00:00], "Etc/UTC"),
     DateTime.new!(Date.add(to, 2), ~T[00:00:00], "Etc/UTC")}
  end

  defp lessee_name(nil), do: nil
  defp lessee_name(user), do: user.display_name || to_string(user.email || "")
end
