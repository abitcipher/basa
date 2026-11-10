defmodule BasaWeb.WidgetEventsTest do
  use ExUnit.Case, async: true

  alias BasaWeb.WidgetEvents

  test "the TypeScript packet types match the catalog" do
    ts = File.read!("assets/widgets/src/packets.ts")

    for {component, %{from: from, to: to}} <- WidgetEvents.catalog() do
      assert ts =~ "#{component}: {", "#{component} missing in packets.ts"

      for type <- from ++ to,
          do: assert(ts =~ ~s("#{type}"), "#{component} #{type} missing in packets.ts")
    end
  end

  test "only catalog packets go to widgets" do
    socket = %Phoenix.LiveView.Socket{}

    assert %Phoenix.LiveView.Socket{} =
             WidgetEvents.push(socket, "c", "AvailabilityCalendar", "availability.changed", %{})

    assert_raise ArgumentError, fn ->
      WidgetEvents.push(socket, "c", "AvailabilityCalendar", "slot.picked")
    end

    assert_raise ArgumentError, fn ->
      WidgetEvents.push(socket, "c", "Nope", "availability.changed")
    end
  end
end
