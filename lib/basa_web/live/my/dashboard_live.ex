defmodule BasaWeb.My.DashboardLive do
  use BasaWeb, :live_view

  alias Basa.Catalog

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       page_title: gettext("My offers"),
       promote: nil,
       payments?: Basa.Payments.enabled?(),
       import?:
         Basa.Import.enabled?() and Basa.Import.status(socket.assigns.current_user) != :none
     )
     |> load()}
  end

  @impl true
  def handle_event("submit", %{"id" => id}, socket) do
    actor = socket.assigns.current_user
    lot = Catalog.get_lot!(id, actor: actor)

    socket =
      case Catalog.submit_lot(lot, actor: actor) do
        {:ok, %{state: :published}} ->
          put_flash(socket, :info, gettext("Published. Lessees can book it now."))

        {:ok, %{state: :under_review}} ->
          put_flash(socket, :info, gettext("Sent for review. We'll let you know."))

        {:ok, %{state: :draft}} ->
          put_flash(socket, :error, gettext("Not published yet: see the notes below the offer."))

        {:error, _} ->
          put_flash(socket, :error, gettext("Could not submit the offer."))
      end

    {:noreply, load(socket)}
  end

  def handle_event("promote", %{"id" => id}, socket) do
    {:noreply, assign(socket, promote: Enum.find(socket.assigns.lots, &(&1.id == id)))}
  end

  def handle_event("close_promote", _, socket), do: {:noreply, assign(socket, promote: nil)}

  def handle_event("buy", %{"product" => product}, socket) do
    product = String.to_existing_atom(product)

    case Basa.Payments.start_premium(socket.assigns.promote.id, product,
           actor: socket.assigns.current_user
         ) do
      {:ok, payment} ->
        {:noreply, redirect(socket, external: payment.payment_url)}

      {:error, error} ->
        {:noreply,
         socket
         |> assign(promote: nil)
         |> put_flash(:error, Enum.join(BasaWeb.ErrorText.messages(error), " "))}
    end
  end

  def handle_event("archive", %{"id" => id}, socket) do
    actor = socket.assigns.current_user
    Catalog.get_lot!(id, actor: actor) |> Catalog.archive_lot!(actor: actor)
    {:noreply, socket |> put_flash(:info, gettext("Offer archived.")) |> load()}
  end

  defp load(socket) do
    actor = socket.assigns.current_user

    assign(socket,
      items: Catalog.list_my_items!(actor: actor),
      baskets: Catalog.list_my_baskets!(actor: actor),
      rooms: Catalog.list_my_rooms!(actor: actor, load: [:geo_city]),
      lots: Catalog.list_my_lots!(actor: actor, load: [room: [:geo_city]]),
      hidden_photos: Basa.Moderation.list_my_hidden!(actor: actor)
    )
  end

  @impl true
  def handle_info({:payment_settled, _id}, socket), do: {:noreply, load(socket)}
  def handle_info(_other, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} unread={@unread_count} active={:my}>
      <.page_title title={gettext("My offers")} help="owner-getting-started">
        <:action>
          <.button_link navigate={~p"/my/photos"} size="small" variant="bordered" icon="hero-photo">
            {gettext("Photos")}
          </.button_link>
          <.button_link
            :if={@import?}
            id="import-link"
            navigate={~p"/my/import"}
            size="small"
            variant="bordered"
            icon="hero-arrow-down-tray"
          >
            {gettext("Import")}
          </.button_link>
          <.button_link
            navigate={~p"/my/stats"}
            size="small"
            variant="bordered"
            icon="hero-chart-bar"
          >
            {gettext("Stats")}
          </.button_link>
          <.button_link
            navigate={~p"/my/schedule"}
            size="small"
            variant="bordered"
            icon="hero-calendar-days"
          >
            {gettext("Schedule")}
          </.button_link>
        </:action>
      </.page_title>

      <ol class="mb-8 grid grid-cols-2 gap-3 sm:grid-cols-4">
        <.step
          n="1"
          title={gettext("Items")}
          count={length(@items)}
          to={~p"/my/items"}
          hint={gettext("Photograph your gear")}
        />
        <.step
          n="2"
          title={gettext("Baskets")}
          count={length(@baskets)}
          to={~p"/my/baskets/new"}
          hint={gettext("Bundle what you rent together")}
        />
        <.step
          n="3"
          title={gettext("Rooms")}
          count={length(@rooms)}
          to={~p"/my/rooms/new"}
          hint={gettext("Where it happens")}
        />
        <.step
          n="4"
          title={gettext("Offers")}
          count={length(@lots)}
          to={~p"/my/lots/new"}
          hint={gettext("Schedule, price, publish")}
        />
      </ol>

      <.card
        :if={@hidden_photos != []}
        id="hidden-photos"
        padding="medium"
        rounded="large"
        class="mb-6 border border-rose-200 dark:border-rose-900"
      >
        <h2 class="flex items-center gap-1.5 font-semibold">
          {gettext("Hidden photos")}
          <.info_tip id="hidden-photos-info">
            {gettext(
              "Renters don't see these photos after a check. Remove or replace them; if a check got it wrong, an admin can bring a photo back."
            )}
          </.info_tip>
        </h2>
        <ul class="mt-2 space-y-2">
          <li :for={c <- @hidden_photos} id={"hidden-#{c.id}"} class="flex items-center gap-3 text-sm">
            <img
              src={Basa.Storage.url(c.key)}
              alt=""
              class="size-14 shrink-0 rounded-lg object-cover"
            />
            <span>
              {if c.review == :removed,
                do: gettext("Removed by an admin."),
                else: Enum.map_join(c.reasons, " ", &Basa.Moderation.reason_text/1)}
            </span>
          </li>
        </ul>
      </.card>

      <.page_title title={gettext("Offers")} level={2}>
        <:action>
          <.button_link
            navigate={~p"/my/lots/new"}
            size="small"
            color="primary"
            variant="default"
            icon="hero-plus"
          >
            {gettext("New offer")}
          </.button_link>
        </:action>
      </.page_title>

      <div class="space-y-3">
        <.card :for={lot <- @lots} padding="medium" rounded="large">
          <div class="flex justify-between gap-2">
            <div>
              <p class="font-semibold">{lot.title}</p>
              <p class="text-sm opacity-70">
                {lot.room.title} · {ngettext("1 item", "%{count} items", length(lot.basket.items))} · {Basa.Money.format(
                  lot.price_amount,
                  lot.currency
                )} / {unit_label(lot.price_unit)}
              </p>
            </div>
            <div class="flex flex-col items-end gap-1">
              <.state_badge state={lot.state} />
              <.badge
                :if={lot.featured_until && DateTime.after?(lot.featured_until, DateTime.utc_now())}
                color="warning"
                size="extra_small"
                rounded="full"
                variant="default"
              >
                ★ {gettext("Featured until %{date}",
                  date: Calendar.strftime(lot.featured_until, "%d.%m")
                )}
              </.badge>
            </div>
          </div>
          <.alert
            :if={lot.review_note}
            kind={:warning}
            rounded="large"
            class="mt-2 whitespace-pre-line"
          >
            {lot.review_note}
          </.alert>
          <div class="mt-3 flex flex-wrap justify-end gap-2">
            <.button
              :if={lot.state == :published and @payments?}
              phx-click="promote"
              phx-value-id={lot.id}
              size="small"
              color="warning"
              variant="bordered"
              icon="hero-star"
            >
              {gettext("Promote")}
            </.button>
            <.button_link
              :if={lot.state == :published}
              navigate={~p"/lots/#{lot.id}"}
              size="small"
              variant="transparent"
            >{gettext("View")}</.button_link>
            <.button_link navigate={~p"/my/lots/#{lot.id}/edit"} size="small" variant="bordered">{gettext(
              "Edit"
            )}</.button_link>
            <.button
              :if={lot.state == :draft}
              phx-click="submit"
              phx-value-id={lot.id}
              size="small"
              color="primary"
              variant="default"
            >
              {gettext("Publish")}
            </.button>
            <.button
              :if={lot.state in [:draft, :published]}
              phx-click="archive"
              phx-value-id={lot.id}
              data-confirm={gettext("Archive this offer? Existing bookings stay.")}
              size="small"
              variant="transparent"
            >
              {gettext("Archive")}
            </.button>
          </div>
        </.card>
        <.empty_state :if={@lots == []} title={gettext("No offers yet")}>
          {gettext("Start with step 1: add a few items with photos.")}
        </.empty_state>
      </div>

      <div class="mt-8 grid gap-6 sm:grid-cols-2">
        <section>
          <.page_title title={gettext("Baskets")} level={2} />
          <.card padding="small" rounded="large" class="divide-y divide-zinc-200 dark:divide-zinc-800">
            <.link
              :for={b <- @baskets}
              navigate={~p"/my/baskets/#{b.id}/edit"}
              class="flex items-center justify-between px-2 py-2 hover:underline"
            >
              {b.title}
              <.badge size="extra_small" rounded="full">
                {length(b.items) + length(b.attendants)}
              </.badge>
            </.link>
            <p :if={@baskets == []} class="p-2 text-sm opacity-60">{gettext("None yet")}</p>
          </.card>
        </section>
        <section>
          <.page_title title={gettext("Rooms")} level={2} />
          <.card padding="small" rounded="large" class="divide-y divide-zinc-200 dark:divide-zinc-800">
            <.link
              :for={r <- @rooms}
              navigate={~p"/my/rooms/#{r.id}/edit"}
              class="flex items-center justify-between gap-2 px-2 py-2 hover:underline"
            >
              <span>{r.title} <span class="opacity-60">{city_name(r)}</span></span>
              <.badge :if={r.mobile} size="extra_small" variant="bordered" rounded="full">
                {gettext("mobile")}
              </.badge>
            </.link>
            <p :if={@rooms == []} class="p-2 text-sm opacity-60">{gettext("None yet")}</p>
          </.card>
        </section>
      </div>

      <.modal
        :if={@promote}
        id="promote-dialog"
        show
        title={gettext("Promote “%{title}”", title: @promote.title)}
        on_cancel={JS.push("close_promote")}
        rounded="large"
      >
        <p class="text-sm opacity-80">
          {gettext("Featured offers are shown first in search and in the bot.")}
        </p>
        <div class="mt-4 grid gap-2">
          <.button
            :for={product <- Basa.Payments.Products.products()}
            phx-click="buy"
            phx-value-product={product}
            variant="bordered"
            full_width
            phx-disable-with={gettext("Opening payment…")}
          >
            <span class="flex w-full justify-between gap-6">
              <span>{Basa.Payments.Products.label(product)}</span>
              <span class="font-semibold">
                {Basa.Payments.Products.price(product, @promote.currency)
                |> then(fn {a, c} -> Basa.Money.format(a, c) end)}
              </span>
            </span>
          </.button>
        </div>
      </.modal>
    </Layouts.app>
    """
  end

  attr :n, :string, required: true
  attr :title, :string, required: true
  attr :count, :integer, required: true
  attr :to, :string, required: true
  attr :hint, :string, required: true

  defp step(assigns) do
    ~H"""
    <li>
      <.link navigate={@to} class="block h-full">
        <.card
          padding="small"
          rounded="large"
          color={if @count > 0, do: "success", else: "natural"}
          variant={if @count > 0, do: "bordered", else: "base"}
          class="h-full hover:shadow"
        >
          <p class="text-xs opacity-60">{gettext("Step")} {@n}</p>
          <p class="font-semibold">
            {@title}
            <.badge size="extra_small" rounded="full">{@count}</.badge>
          </p>
          <p class="text-xs opacity-70">{@hint}</p>
        </.card>
      </.link>
    </li>
    """
  end
end
