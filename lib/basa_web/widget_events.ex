defmodule BasaWeb.WidgetEvents do
  import Phoenix.LiveView, only: [push_event: 3]
  require Logger

  @packets %{
    "AvailabilityCalendar" => %{from: ["slot.picked"], to: ["availability.changed"]},
    "LessorCalendar" => %{from: ["booking.opened"], to: ["bookings.changed"]},
    "ResourceTimeline" => %{from: ["booking.opened"], to: ["bookings.changed"]},
    "BookingBoard" => %{from: ["booking.moved", "booking.opened"], to: ["bookings.changed"]},
    "LessorStats" => %{from: [], to: ["bookings.changed"]},
    "AdminGrid" => %{from: [], to: []},
    "PhotoLibrary" => %{from: ["photos.deleted"], to: ["photos.changed"]},
    "PhotoGallery" => %{from: [], to: []}
  }

  def catalog, do: @packets

  defp packets(component, direction), do: get_in(@packets, [component, direction]) || []

  def handle(
        %{"widget" => id, "component" => component, "type" => type} = packet,
        socket,
        handler
      )
      when is_binary(id) do
    if type in packets(component, :from) do
      handler.(id, type, packet["data"] || %{}, socket)
    else
      Logger.warning("dropped widget packet #{inspect(component)} #{inspect(type)}")
      {:noreply, socket}
    end
  end

  def handle(packet, socket, _handler) do
    Logger.warning("dropped malformed widget packet #{inspect(packet, limit: 5)}")
    {:noreply, socket}
  end

  def push(socket, id, component, type, data \\ %{}) do
    unless type in packets(component, :to),
      do: raise(ArgumentError, "#{component} doesn't receive #{inspect(type)} packets")

    push_event(socket, "widget:#{id}", %{type: type, data: data})
  end
end
