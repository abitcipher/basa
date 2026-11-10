defmodule BasaWeb.Admin.ReviewLive do
  use BasaWeb, :live_view
  require Ash.Query

  alias Basa.Catalog

  @impl true
  def mount(_params, _session, socket) do
    if socket.assigns.current_user.role == :admin do
      {:ok, socket |> assign(page_title: gettext("Review")) |> load()}
    else
      {:ok, socket |> put_flash(:error, gettext("Admins only.")) |> push_navigate(to: ~p"/")}
    end
  end

  @impl true
  def handle_event("approve", %{"id" => id}, socket) do
    actor = socket.assigns.current_user
    Catalog.get_lot!(id, actor: actor) |> Catalog.approve_lot!(actor: actor)
    {:noreply, socket |> put_flash(:info, gettext("Published.")) |> load()}
  end

  def handle_event("reject", %{"lot_id" => id, "note" => note}, socket) do
    actor = socket.assigns.current_user
    Catalog.get_lot!(id, actor: actor) |> Catalog.reject_lot!(note, actor: actor)
    {:noreply, socket |> put_flash(:info, gettext("Sent back to the lessor.")) |> load()}
  end

  defp load(socket) do
    lots =
      Basa.Catalog.Lot
      |> Ash.Query.filter(state == :under_review)
      |> Ash.Query.load([:room, basket: [:items]])
      |> Ash.read!(actor: socket.assigns.current_user)

    assign(socket, lots: lots)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} unread={@unread_count}>
      <.page_title title={gettext("Offers waiting for review")} />
      <.card :for={lot <- @lots} padding="medium" rounded="large" class="mb-3">
        <p class="font-semibold">{lot.title}</p>
        <p class="text-sm opacity-70">
          {city_name(lot.room)} · {Enum.map_join(lot.basket.items, ", ", & &1.title)}
        </p>
        <form phx-submit="reject" class="mt-2 flex flex-wrap items-end gap-2">
          <input type="hidden" name="lot_id" value={lot.id} />
          <div class="min-w-48 flex-1">
            <.text_field
              name="note"
              required
              placeholder={gettext("Why is it sent back?")}
              size="small"
            />
          </div>
          <.button type="submit" size="small" variant="bordered">{gettext("Send back")}</.button>
          <.button
            type="button"
            size="small"
            color="primary"
            variant="default"
            phx-click="approve"
            phx-value-id={lot.id}
          >{gettext("Approve")}</.button>
        </form>
      </.card>
      <.empty_state :if={@lots == []} title={gettext("Nothing to review")} icon="hero-check-circle" />
    </Layouts.app>
    """
  end
end
