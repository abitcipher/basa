defmodule BasaWeb.AppHomeLive do
  use BasaWeb, :live_view

  @impl true
  def mount(_params, _session, socket), do: {:ok, assign(socket, page_title: "BASA")}

  defp tiles do
    [
      %{id: "find", icon: "hero-magnifying-glass", label: gettext("Find"), path: ~p"/"},
      %{
        id: "bookings",
        icon: "hero-calendar-days",
        label: gettext("Bookings"),
        path: ~p"/bookings"
      },
      %{
        id: "messages",
        icon: "hero-chat-bubble-left-right",
        label: gettext("Messages"),
        path: ~p"/messages"
      },
      %{id: "offers", icon: "hero-squares-2x2", label: gettext("My offers"), path: ~p"/my"},
      %{id: "schedule", icon: "hero-clock", label: gettext("Schedule"), path: ~p"/my/schedule"},
      %{id: "add", icon: "hero-camera", label: gettext("Add item"), path: ~p"/my/items/new"},
      %{id: "profile", icon: "hero-user-circle", label: gettext("Profile"), path: ~p"/profile"},
      %{id: "help", icon: "hero-question-mark-circle", label: gettext("Help"), path: ~p"/help"}
    ]
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, tiles: tiles())

    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} unread={@unread_count}>
      <div id="app-home" class="mx-auto max-w-md">
        <p :if={@current_user} class="mb-4 text-lg font-semibold">
          {gettext("Hi, %{name}!", name: BasaWeb.Layouts.display_name(@current_user))}
        </p>
        <BasaTma.Components.tiles :let={tile} id="app-tiles" tiles={@tiles}>
          <.icon name={tile.icon} class="size-7" />
        </BasaTma.Components.tiles>
      </div>
    </Layouts.app>
    """
  end
end
