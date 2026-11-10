defmodule Basa.Bookings.Availability do
  require Ash.Query

  alias Basa.Bookings.{Claim, Schedule}

  def busy(lot, %DateTime{} = from, %DateTime{} = to) do
    lot = Ash.load!(lot, [basket: [:items, :attendants]], authorize?: false, lazy?: true)
    item_ids = Enum.map(lot.basket.items, & &1.id)
    attendant_ids = Enum.map(lot.basket.attendants, & &1.id)

    Claim
    |> Ash.Query.filter(
      active == true and starts_at < ^to and ends_at > ^from and
        ((resource_type == :room and resource_id == ^lot.room_id) or
           (resource_type == :item and resource_id in ^item_ids) or
           (resource_type == :attendant and resource_id in ^attendant_ids))
    )
    |> Ash.Query.select([:starts_at, :ends_at])
    |> Ash.read!(authorize?: false)
    |> Enum.map(&{&1.starts_at, &1.ends_at})
  end

  def slots(lot, %Date{} = date, now \\ DateTime.utc_now()) do
    candidates = Schedule.candidate_slots(lot, date)

    case candidates do
      [] ->
        []

      [{first, _} | _] ->
        {_, last} = List.last(candidates)
        busy = busy(lot, first, last)
        earliest = DateTime.add(now, (lot.lead_time_hours || 0) * 3600, :second)

        for {s, e} <- candidates do
          taken? =
            DateTime.compare(s, earliest) == :lt or
              Enum.any?(busy, fn {bs, be} ->
                DateTime.compare(s, be) == :lt and DateTime.compare(e, bs) == :gt
              end)

          %{starts_at: s, ends_at: e, free?: not taken?}
        end
    end
  end

  def days(lot, %Date{} = from, count, now \\ DateTime.utc_now()) do
    dates = Enum.map(0..(count - 1), &Date.add(from, &1))
    candidates = Map.new(dates, &{&1, Schedule.candidate_slots(lot, &1)})
    all = candidates |> Map.values() |> List.flatten()

    busy =
      case all do
        [] ->
          []

        _ ->
          first = all |> Enum.map(&elem(&1, 0)) |> Enum.min(DateTime)
          last = all |> Enum.map(&elem(&1, 1)) |> Enum.max(DateTime)
          busy(lot, first, last)
      end

    earliest = DateTime.add(now, (lot.lead_time_hours || 0) * 3600, :second)

    for date <- dates do
      slots =
        for {s, e} <- candidates[date] do
          taken? =
            DateTime.compare(s, earliest) == :lt or
              Enum.any?(busy, fn {bs, be} ->
                DateTime.compare(s, be) == :lt and DateTime.compare(e, bs) == :gt
              end)

          %{starts_at: s, ends_at: e, free: not taken?}
        end

      %{date: date, free: Enum.count(slots, & &1.free), total: length(slots), slots: slots}
    end
  end

  def free?(lot, from, to) do
    to = DateTime.add(to, (lot.buffer_minutes || 0) * 60, :second)
    busy(lot, from, to) == []
  end
end
