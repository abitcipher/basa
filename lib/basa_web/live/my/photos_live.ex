defmodule BasaWeb.My.PhotosLive do
  use BasaWeb, :live_view

  alias Basa.Catalog
  alias BasaWeb.WidgetEvents

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(page_title: gettext("Photos")) |> load()}
  end

  @impl true
  def handle_event("widget:event", packet, socket),
    do: WidgetEvents.handle(packet, socket, &widget_event/4)

  def handle_event("delete_photo", %{"owner" => owner, "id" => id, "key" => key}, socket),
    do: {:noreply, delete(socket, [%{"owner" => owner, "id" => id, "key" => key}])}

  defp widget_event(_widget, "photos.deleted", %{"photos" => photos}, socket)
       when is_list(photos),
       do: {:noreply, delete(socket, photos)}

  defp widget_event(_widget, _type, _data, socket), do: {:noreply, socket}

  defp delete(socket, photos) do
    actor = socket.assigns.current_user

    results =
      photos
      |> Enum.group_by(&{&1["owner"], &1["id"]}, & &1["key"])
      |> Enum.map(fn {{owner, id}, keys} -> remove(owner, id, keys, actor) end)

    socket =
      if Enum.all?(results, &match?({:ok, _}, &1)),
        do: put_flash(socket, :info, gettext("Done.")),
        else: put_flash(socket, :error, gettext("That didn't work. Please try again."))

    if socket.assigns.widgets?,
      do: WidgetEvents.push(socket, "photo-library", "PhotoLibrary", "photos.changed"),
      else: load(socket)
  end

  defp remove("item", id, keys, actor) do
    with {:ok, item} <- Catalog.get_item(id, actor: actor),
         do: Catalog.update_item(item, %{photos: item.photos -- keys}, actor: actor)
  end

  defp remove("room", id, keys, actor) do
    with {:ok, room} <- Catalog.get_room(id, actor: actor),
         do: Catalog.update_room(room, %{photos: room.photos -- keys}, actor: actor)
  end

  defp remove(_owner, _id, _keys, _actor), do: {:error, :unknown}

  defp load(%{assigns: %{widgets?: true}} = socket), do: socket

  defp load(socket) do
    actor = socket.assigns.current_user

    assign(socket,
      groups: [
        {"item", gettext("Items"), Catalog.list_my_items!(actor: actor)},
        {"room", gettext("Rooms"), Catalog.list_my_rooms!(actor: actor)}
      ]
    )
  end

  defp props do
    %{
      locale: Gettext.get_locale(BasaWeb.Gettext),
      labels: %{
        items: gettext("Items"),
        rooms: gettext("Rooms"),
        error: gettext("Couldn't load the photos."),
        retry: gettext("Try again")
      }
    }
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} unread={@unread_count} active={:my} wide>
      <.page_title title={gettext("Photos")} info_id="photos-info" help="photos">
        <:info>
          {gettext("All photos of your items and rooms. Add new ones in the item or room form.")}
        </:info>
      </.page_title>

      <.widget id="photo-library" component="PhotoLibrary" props={props()} enabled={@widgets?}>
        <:loading>
          <div class="h-[70vh] animate-pulse rounded-xl bg-zinc-100 dark:bg-zinc-800"></div>
        </:loading>
        <:fallback>
          <section :for={{owner, title, records} <- @groups} class="mb-6">
            <h2 class="mb-2 font-semibold">{title}</h2>
            <div :for={r <- records} :if={r.photos != []} class="mb-3">
              <p class="mb-1 text-sm opacity-80">{r.title}</p>
              <div class="flex flex-wrap gap-2">
                <div
                  :for={key <- r.photos}
                  id={"photo-#{owner}-#{r.id}-#{key |> String.replace(~r/[^a-zA-Z0-9]/, "-")}"}
                  class="relative size-24 overflow-hidden rounded-lg"
                >
                  <a href={Basa.Storage.url(key)} target="_blank"><.photo key={key} /></a>
                  <button
                    type="button"
                    phx-click="delete_photo"
                    phx-value-owner={owner}
                    phx-value-id={r.id}
                    phx-value-key={key}
                    data-confirm={gettext("Remove this photo?")}
                    class="absolute top-1 right-1 cursor-pointer rounded-full bg-white/90 p-0.5 text-zinc-800"
                    aria-label={gettext("Remove photo")}
                  >
                    <.icon name="hero-trash" class="size-4" />
                  </button>
                </div>
              </div>
            </div>
          </section>
        </:fallback>
      </.widget>
    </Layouts.app>
    """
  end
end
