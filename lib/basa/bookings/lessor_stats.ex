defmodule Basa.Bookings.LessorStats do
  require Ash.Query
  alias Basa.Bookings.{Booking, Schedule}
  alias Basa.Catalog.Lot

  @counted [:confirmed, :completed]

  def compute(owner, %Date{} = from, %Date{} = to) do
    lots =
      Lot
      |> Ash.Query.filter(owner_id == ^owner.id and state != :archived)
      |> Ash.Query.sort(title: :asc)
      |> Ash.read!(authorize?: false)

    starts = DateTime.new!(from, ~T[00:00:00], "Etc/UTC")
    ends = DateTime.new!(Date.add(to, 1), ~T[00:00:00], "Etc/UTC")

    bookings =
      Booking
      |> Ash.Query.filter(
        owner_id == ^owner.id and status in ^@counted and starts_at >= ^starts and
          starts_at < ^ends
      )
      |> Ash.read!(authorize?: false)

    by_lot = Enum.group_by(bookings, & &1.lot_id)
    currency = main_currency(lots)

    %{
      currency: currency,
      offers: Enum.map(lots, &offer(&1, by_lot[&1.id] || [], from, to)),
      weeks: weeks(bookings, from, to, currency)
    }
  end

  defp offer(lot, bookings, from, to) do
    open =
      Date.range(from, to)
      |> Enum.flat_map(&Schedule.candidate_slots(lot, &1))
      |> Enum.map(fn {s, e} -> DateTime.diff(e, s, :minute) end)
      |> Enum.sum()

    booked = bookings |> Enum.map(&DateTime.diff(&1.ends_at, &1.starts_at, :minute)) |> Enum.sum()

    %{
      lot_id: lot.id,
      title: lot.title,
      open_hours: div(open, 60),
      booked_hours: div(booked, 60),
      occupancy: if(open > 0, do: Float.round(min(booked / open, 1.0) * 100, 1), else: 0.0),
      bookings: length(bookings),
      earnings:
        bookings |> Enum.map(& &1.price_amount) |> Enum.reduce(Decimal.new(0), &Decimal.add/2),
      currency: lot.currency
    }
  end

  defp weeks(bookings, from, to, currency) do
    by_week = Enum.group_by(bookings, &monday(DateTime.to_date(&1.starts_at)))

    monday(from)
    |> Stream.iterate(&Date.add(&1, 7))
    |> Enum.take_while(&(Date.compare(&1, to) != :gt))
    |> Enum.map(fn week ->
      in_week = by_week[week] || []

      %{
        week: week,
        bookings: length(in_week),
        earnings:
          in_week
          |> Enum.filter(&(&1.currency == currency))
          |> Enum.map(& &1.price_amount)
          |> Enum.reduce(Decimal.new(0), &Decimal.add/2)
      }
    end)
  end

  defp monday(date), do: Date.add(date, 1 - Date.day_of_week(date))

  defp main_currency([]), do: :UAH

  defp main_currency(lots),
    do: lots |> Enum.frequencies_by(& &1.currency) |> Enum.max_by(&elem(&1, 1)) |> elem(0)
end
