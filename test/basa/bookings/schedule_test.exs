defmodule Basa.Bookings.ScheduleTest do
  use ExUnit.Case, async: true

  alias Basa.Bookings.Schedule

  defp lot(attrs) do
    Map.merge(
      %{
        price_amount: Decimal.new(100),
        price_unit: :hour,
        slot_minutes: nil,
        min_units: 1,
        max_units: nil,
        lead_time_hours: 0,
        weekly_hours: %{},
        timezone: "Europe/Kyiv"
      },
      attrs
    )
  end

  @now ~U[2026-11-02 06:00:00Z]

  test "hours round up" do
    assert {:ok, 2} = Schedule.units(lot(%{}), ~U[2026-11-03 10:00:00Z], ~U[2026-11-03 11:30:00Z])
  end

  test "slots must fit exactly" do
    l = lot(%{price_unit: :slot, slot_minutes: 90})
    assert {:ok, 2} = Schedule.units(l, ~U[2026-11-03 10:00:00Z], ~U[2026-11-03 13:00:00Z])

    assert {:error, :ends_at, _} =
             Schedule.units(l, ~U[2026-11-03 10:00:00Z], ~U[2026-11-03 12:00:00Z])
  end

  test "quote prices the units and checks lead time and limits" do
    l = lot(%{lead_time_hours: 12, max_units: 4})

    assert {:ok, %{units: 3, price: price}} =
             Schedule.quote(l, ~U[2026-11-03 10:00:00Z], ~U[2026-11-03 13:00:00Z], @now)

    assert Decimal.equal?(price, 300)

    assert {:error, :starts_at, _} =
             Schedule.quote(l, ~U[2026-11-02 08:00:00Z], ~U[2026-11-02 09:00:00Z], @now)

    assert {:error, :ends_at, _} =
             Schedule.quote(l, ~U[2026-11-03 10:00:00Z], ~U[2026-11-03 16:00:00Z], @now)
  end

  test "opening hours are read in the lot's local time" do
    l = lot(%{weekly_hours: %{"2" => [["09:00", "18:00"]]}})
    assert :ok = Schedule.within_hours(l, ~U[2026-11-03 07:00:00Z], ~U[2026-11-03 09:00:00Z])

    assert {:error, _, _} =
             Schedule.within_hours(l, ~U[2026-11-03 06:00:00Z], ~U[2026-11-03 08:00:00Z])
  end

  test "candidate slots follow opening hours and step" do
    l = lot(%{weekly_hours: %{"2" => [["10:00", "13:00"]]}, timezone: "Etc/UTC"})
    slots = Schedule.candidate_slots(l, ~D[2026-11-03])
    assert length(slots) == 3
    assert {~U[2026-11-03 10:00:00Z], ~U[2026-11-03 11:00:00Z]} = hd(slots)
    assert Schedule.candidate_slots(l, ~D[2026-11-04]) == []
  end

  test "weekly hours shape is validated" do
    assert :ok = Schedule.validate_weekly_hours(%{"1" => [["09:00", "24:00"]]})
    assert {:error, _} = Schedule.validate_weekly_hours(%{"8" => [["09:00", "10:00"]]})
    assert {:error, _} = Schedule.validate_weekly_hours(%{"1" => [["18:00", "09:00"]]})
  end
end
