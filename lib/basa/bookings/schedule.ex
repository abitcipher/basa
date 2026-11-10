defmodule Basa.Bookings.Schedule do
  @weekdays ~w(1 2 3 4 5 6 7)

  def validate_weekly_hours(hours) when is_map(hours) do
    Enum.reduce_while(hours, :ok, fn {day, ranges}, :ok ->
      cond do
        to_string(day) not in @weekdays ->
          {:halt, {:error, "uses an unknown weekday #{inspect(day)}"}}

        not is_list(ranges) or not Enum.all?(ranges, &valid_range?/1) ->
          {:halt, {:error, "has an invalid time range on day #{day}"}}

        true ->
          {:cont, :ok}
      end
    end)
  end

  def validate_weekly_hours(_), do: {:error, "must be a map"}

  defp valid_range?([from, to]) do
    with {:ok, f} <- parse_time(from), {:ok, t} <- parse_time(to) do
      Time.compare(f, t) == :lt or to == "24:00"
    else
      _ -> false
    end
  end

  defp valid_range?(_), do: false

  defp parse_time("24:00"), do: {:ok, ~T[23:59:59]}
  defp parse_time(value) when is_binary(value), do: Time.from_iso8601(value <> ":00")
  defp parse_time(_), do: :error

  def quote(lot, %DateTime{} = starts_at, %DateTime{} = ends_at, now \\ DateTime.utc_now()) do
    with :ok <- ordered(starts_at, ends_at),
         :ok <- lead_time(lot, starts_at, now),
         {:ok, units} <- units(lot, starts_at, ends_at),
         :ok <- unit_limits(lot, units),
         :ok <- within_hours(lot, starts_at, ends_at),
         :ok <- one_handover(lot, units) do
      {:ok, %{units: units, price: price(lot, units)}}
    end
  end

  defp one_handover(%{deal: :sale}, units) when units != 1,
    do: {:error, :ends_at, Basa.I18n.t("pick one handover time")}

  defp one_handover(_lot, _units), do: :ok

  defp price(%{deal: :sale} = lot, _units), do: lot.price_amount
  defp price(lot, units), do: Decimal.mult(lot.price_amount, units)

  defp ordered(s, e) do
    if DateTime.compare(s, e) == :lt,
      do: :ok,
      else: {:error, :ends_at, Basa.I18n.t("must be after the start")}
  end

  defp lead_time(lot, starts_at, now) do
    earliest = DateTime.add(now, (lot.lead_time_hours || 0) * 3600, :second)

    cond do
      DateTime.compare(starts_at, now) == :lt ->
        {:error, :starts_at, Basa.I18n.t("is in the past")}

      DateTime.compare(starts_at, earliest) == :lt ->
        {:error, :starts_at,
         Basa.I18n.t("must be at least %{hours} h from now", hours: lot.lead_time_hours)}

      true ->
        :ok
    end
  end

  def units(lot, starts_at, ends_at) do
    minutes = DateTime.diff(ends_at, starts_at, :minute)

    case lot.price_unit do
      :hour ->
        {:ok, ceil_div(minutes, 60)}

      :day ->
        {:ok, ceil_div(minutes, 24 * 60)}

      :slot ->
        slot = lot.slot_minutes

        if rem(minutes, slot) == 0,
          do: {:ok, div(minutes, slot)},
          else:
            {:error, :ends_at,
             Basa.I18n.t("must cover whole %{minutes}-minute slots", minutes: slot)}
    end
  end

  defp ceil_div(a, b), do: div(a + b - 1, b)

  defp unit_limits(lot, units) do
    cond do
      units < (lot.min_units || 1) ->
        {:error, :ends_at,
         Basa.I18n.t("is shorter than the minimum of %{units}", units: lot.min_units)}

      lot.max_units && units > lot.max_units ->
        {:error, :ends_at,
         Basa.I18n.t("is longer than the maximum of %{units}", units: lot.max_units)}

      true ->
        :ok
    end
  end

  def within_hours(lot, starts_at, ends_at) do
    hours = lot.weekly_hours || %{}

    if hours == %{} or lot.price_unit == :day do
      :ok
    else
      local_start = DateTime.shift_zone!(starts_at, lot.timezone)
      local_end = DateTime.shift_zone!(ends_at, lot.timezone)
      date = DateTime.to_date(local_start)
      ranges = Map.get(hours, to_string(Date.day_of_week(date)), [])
      same_day? = Date.compare(DateTime.to_date(local_end), date) == :eq or midnight?(local_end)

      fits? =
        same_day? and
          Enum.any?(ranges, fn [from, to] ->
            t_start = DateTime.to_time(local_start)
            t_end = if midnight?(local_end), do: ~T[23:59:59], else: DateTime.to_time(local_end)
            {:ok, f} = parse_time(from)
            {:ok, t} = parse_time(to)
            Time.compare(t_start, f) != :lt and Time.compare(t_end, t) != :gt
          end)

      if fits?, do: :ok, else: {:error, :starts_at, Basa.I18n.t("is outside the opening hours")}
    end
  end

  defp midnight?(%DateTime{hour: 0, minute: 0, second: 0}), do: true
  defp midnight?(_), do: false

  def candidate_slots(lot, %Date{} = date) do
    step =
      case lot.price_unit do
        :hour -> 60
        :slot -> lot.slot_minutes
        :day -> 24 * 60
      end

    ranges =
      case {lot.price_unit, Map.get(lot.weekly_hours || %{}, to_string(Date.day_of_week(date)))} do
        {:day, _} -> [["00:00", "24:00"]]
        {_, nil} when lot.weekly_hours in [nil, %{}] -> [["00:00", "24:00"]]
        {_, nil} -> []
        {_, list} -> list
      end

    for [from, to] <- ranges,
        start_min = to_minutes(from),
        end_min = to_minutes(to),
        m <- Stream.iterate(start_min, &(&1 + step)) |> Enum.take_while(&(&1 + step <= end_min)) do
      local = DateTime.new!(date, ~T[00:00:00], lot.timezone) |> DateTime.add(m * 60, :second)
      s = DateTime.shift_zone!(local, "Etc/UTC")
      {s, DateTime.add(s, step * 60, :second)}
    end
  end

  defp to_minutes("24:00"), do: 24 * 60

  defp to_minutes(hhmm) do
    [h, m] = String.split(hhmm, ":")
    String.to_integer(h) * 60 + String.to_integer(m)
  end
end
