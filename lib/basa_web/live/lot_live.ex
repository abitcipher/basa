defmodule BasaWeb.LotLive do
  use BasaWeb, :live_view

  alias Basa.Bookings
  alias Basa.Bookings.{Availability, Schedule}
  alias Basa.Catalog
  alias BasaWeb.WidgetEvents

  @calendar_days 56
  @fallback_days 14

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    actor = socket.assigns.current_user

    case Catalog.get_lot(id,
           actor: actor,
           load: [room: [:geo_city], basket: [:items, :attendants]]
         ) do
      {:ok, lot} ->
        if connected?(socket), do: Basa.Events.subscribe_availability(lot.owner_id)

        {:ok,
         socket
         |> assign(page_title: lot.title, lot: lot, own?: !!actor and actor.id == lot.owner_id)
         |> assign(credits: lot |> photos() |> Basa.Images.credits() |> Map.values())
         |> assign(today: local_today(lot), date: local_today(lot))
         |> assign(start: nil, units: lot.min_units, quote: nil, note: "", booking_error: nil)
         |> load_slots()}

      {:error, _} ->
        {:ok,
         socket
         |> put_flash(:error, gettext("This offer is not available."))
         |> push_navigate(to: ~p"/")}
    end
  end

  @impl true
  def handle_event("pick_date", %{"date" => date}, socket) do
    {:noreply,
     socket |> assign(date: Date.from_iso8601!(date), start: nil, quote: nil) |> load_slots()}
  end

  def handle_event("pick_slot", %{"start" => start}, socket),
    do: {:noreply, pick_slot(socket, start)}

  def handle_event("widget:event", packet, socket),
    do: WidgetEvents.handle(packet, socket, &widget_event/4)

  def handle_event("units", %{"delta" => delta}, socket) do
    lot = socket.assigns.lot
    units = socket.assigns.units + String.to_integer(delta)
    units = units |> max(lot.min_units) |> min(lot.max_units || 1000)
    {:noreply, socket |> assign(units: units) |> requote()}
  end

  def handle_event("message_lessor", _, socket) do
    case socket.assigns.current_user do
      nil ->
        {:noreply, push_navigate(socket, to: ~p"/sign-in")}

      user ->
        case Basa.Messaging.start_conversation(socket.assigns.lot.id, actor: user) do
          {:ok, conv} ->
            {:noreply, push_navigate(socket, to: ~p"/messages/#{conv.id}")}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, gettext("Couldn't open the conversation."))}
        end
    end
  end

  def handle_event("close_dialog", _, socket),
    do: {:noreply, assign(socket, start: nil, quote: nil)}

  def handle_event("book", %{"note" => note}, socket) do
    %{lot: lot, start: start} = socket.assigns

    case Bookings.book(
           %{lot_id: lot.id, starts_at: start, ends_at: period_end(socket), note: note},
           actor: socket.assigns.current_user
         ) do
      {:ok, booking} ->
        message =
          if booking.status == :confirmed,
            do: gettext("Booked! See you there."),
            else: gettext("Request sent. The slot is held while the lessor confirms.")

        {:noreply, socket |> put_flash(:info, message) |> push_navigate(to: ~p"/bookings")}

      {:error, error} ->
        {:noreply,
         socket
         |> assign(booking_error: error_message(error))
         |> availability_changed()}
    end
  end

  @impl true
  def handle_info({:availability_changed, _owner_id}, socket) do
    socket = availability_changed(socket)

    socket =
      if socket.assigns.start &&
           !Availability.free?(socket.assigns.lot, socket.assigns.start, period_end(socket)),
         do:
           assign(socket,
             booking_error: gettext("Someone just booked this time. Please pick another slot.")
           ),
         else: socket

    {:noreply, socket}
  end

  def handle_info(_other, socket), do: {:noreply, socket}

  defp widget_event("lot-calendar", "slot.picked", %{"startsAt" => start}, socket),
    do: {:noreply, pick_slot(socket, start)}

  defp widget_event(_widget, _type, _data, socket), do: {:noreply, socket}

  defp pick_slot(socket, start) do
    with false <- socket.assigns.own?,
         {:ok, start, _} <- DateTime.from_iso8601(start) do
      socket |> assign(start: start, booking_error: nil) |> requote()
    else
      _ -> socket
    end
  end

  defp availability_changed(%{assigns: %{widgets?: true}} = socket),
    do:
      WidgetEvents.push(socket, "lot-calendar", "AvailabilityCalendar", "availability.changed", %{
        lotId: socket.assigns.lot.id
      })

  defp availability_changed(socket), do: load_slots(socket)

  defp load_slots(%{assigns: %{widgets?: true}} = socket), do: socket

  defp load_slots(socket) do
    today = socket.assigns.today

    assign(socket,
      days: Enum.map(0..(@fallback_days - 1), &Date.add(today, &1)),
      slots: Availability.slots(socket.assigns.lot, socket.assigns.date)
    )
  end

  defp local_time(dt, lot),
    do: dt |> DateTime.shift_zone!(lot.timezone) |> Calendar.strftime("%H:%M")

  defp calendar_props(assigns) do
    %{
      lotId: assigns.lot.id,
      today: Date.to_iso8601(assigns.today),
      timezone: assigns.lot.timezone,
      locale: Gettext.get_locale(BasaWeb.Gettext),
      days: @calendar_days,
      wholeDay: assigns.lot.price_unit == :day,
      readOnly: assigns.own?,
      labels: %{
        closed: gettext("Closed on this day."),
        full: gettext("Fully booked on this day."),
        wholeDay: gettext("Whole day"),
        legendFree: gettext("Free"),
        legendFew: gettext("Few left"),
        legendFull: gettext("Booked"),
        error: gettext("Couldn't load the free times."),
        retry: gettext("Try again")
      }
    }
  end

  defp gallery_props(lot) do
    %{
      photos: Enum.map(photos(lot), &%{src: Basa.Storage.url(&1), alt: lot.title}),
      labels: %{
        open: gettext("Open photo"),
        close: gettext("Close"),
        previous: gettext("Previous photo"),
        next: gettext("Next photo"),
        more: gettext("+%{count}", count: "%{count}")
      }
    }
  end

  defp requote(%{assigns: %{start: nil}} = socket), do: assign(socket, quote: nil)

  defp requote(socket) do
    %{lot: lot, start: start} = socket.assigns
    ends_at = period_end(socket)

    quote =
      with {:ok, q} <- Schedule.quote(lot, start, ends_at),
           true <-
             Availability.free?(lot, start, ends_at) ||
               {:error, :starts_at, gettext("part of this time is taken")} do
        {:ok, Map.put(q, :ends_at, ends_at)}
      end

    assign(socket, quote: quote)
  end

  defp period_end(%{assigns: %{lot: lot, start: start, units: units}}) do
    minutes =
      case lot.price_unit do
        :hour -> 60
        :day -> 24 * 60
        :slot -> lot.slot_minutes
      end

    DateTime.add(start, units * minutes * 60, :second)
  end

  defp local_today(lot), do: DateTime.now!(lot.timezone) |> DateTime.to_date()

  defp local_datetime(dt, lot),
    do: dt |> DateTime.shift_zone!(lot.timezone) |> Calendar.strftime("%d.%m %H:%M")

  defp error_message(%{errors: [error | _]}),
    do: error |> BasaWeb.ErrorText.messages() |> hd() |> strip_field()

  defp error_message(error), do: Exception.message(error)

  defp strip_field(text), do: text |> String.split(": ", parts: 2) |> List.last()

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} unread={@unread_count} active={:find}>
      <.back_button navigate={~p"/"} label={gettext("Back")} class="mb-1.5" />

      <div class="mb-4">
        <.widget
          :if={photos(@lot) != []}
          id="lot-gallery"
          component="PhotoGallery"
          props={gallery_props(@lot)}
          enabled={@widgets?}
        >
          <:loading>
            <div class="aspect-video overflow-hidden rounded-xl">
              <.photo key={cover(@lot)} alt={@lot.title} />
            </div>
          </:loading>
          <:fallback>
            <div class="aspect-video overflow-hidden rounded-xl">
              <.photo key={cover(@lot)} alt={@lot.title} />
            </div>
            <div :if={length(photos(@lot)) > 1} class="mt-2 grid grid-cols-4 gap-2 sm:grid-cols-6">
              <a
                :for={key <- tl(photos(@lot))}
                href={Basa.Storage.url(key)}
                target="_blank"
                class="aspect-square overflow-hidden rounded-lg"
              >
                <.photo key={key} alt={@lot.title} />
              </a>
            </div>
          </:fallback>
        </.widget>
        <div :if={photos(@lot) == []} class="aspect-video overflow-hidden rounded-xl">
          <.photo key={cover(@lot)} />
        </div>
        <.photo_credits id="photo-credits" credits={@credits} />
      </div>

      <div class="flex items-start justify-between gap-4">
        <div>
          <h1 class="text-2xl font-bold">{@lot.title}</h1>
          <p class="opacity-70">
            {@lot.room.title} · {city_name(@lot.room)}<span :if={@lot.room.address}>, {@lot.room.address}</span>
            <span class="ml-1" title={gettext("Placement")}>{Basa.Catalog.Room.placement_marker(
              @lot.room.placement
            )}</span>
          </p>
          <p :if={@lot.room.mobile} class="mt-1 text-sm">
            <.badge variant="bordered" size="small" rounded="full">{gettext("Mobile setup")}</.badge>
            {gettext("Comes to you within %{km} km, or you come to it.",
              km: @lot.room.service_radius_km
            )}
          </p>
        </div>
        <div class="shrink-0 text-right">
          <p class="text-xl font-bold">{Basa.Money.format(@lot.price_amount, @lot.currency)}</p>
          <p :if={@lot.deal != :sale} class="text-sm opacity-70">/ {unit_label(@lot.price_unit)}</p>
          <p
            :if={@lot.deal == :sale}
            class="text-sm font-medium text-secondary-light dark:text-secondary-dark"
          >
            {gettext("For sale")}
          </p>
        </div>
      </div>

      <p :if={@lot.description} class="mt-4 whitespace-pre-line">{@lot.description}</p>

      <.button
        :if={!@own?}
        phx-click="message_lessor"
        variant="bordered"
        size="small"
        rounded="large"
        icon="hero-chat-bubble-left-right"
        class="mt-4"
      >
        {gettext("Message the lessor")}
      </.button>

      <section class="mt-6">
        <.page_title title={gettext("Included")} level={2} />
        <div class="grid gap-2 sm:grid-cols-2">
          <.card
            :for={item <- @lot.basket.items}
            padding="small"
            rounded="large"
            class="flex items-center gap-3"
          >
            <div class="size-12 shrink-0 overflow-hidden rounded">
              <.photo key={List.first(item.photos)} />
            </div>
            <div class="text-sm">
              <p class="font-medium">{item.title}</p>
              <p :if={item.brand && item.title != "#{item.brand} #{item.model}"} class="opacity-70">
                {item.brand} {item.model}
              </p>
            </div>
          </.card>
          <.card
            :for={a <- @lot.basket.attendants}
            padding="small"
            rounded="large"
            class="flex items-center gap-3"
          >
            <.avatar size="small" rounded="full" color="natural"><:icon name="hero-user" /></.avatar>
            <div class="text-sm">
              <p class="font-medium">{a.name}</p>
              <p class="opacity-70">{role_label(a.role)}</p>
            </div>
          </.card>
        </div>
      </section>

      <section class="mt-6">
        <.page_title title={gettext("Where")} level={2} />
        <div
          id="lot-map"
          phx-hook="MapPicker"
          phx-update="ignore"
          data-readonly
          data-lat={@lot.room.lat}
          data-lng={@lot.room.lng}
          data-radius-km={@lot.room.mobile && @lot.room.service_radius_km}
          class="relative z-0 h-56 overflow-hidden rounded-xl bg-zinc-100 dark:bg-zinc-800"
        >
        </div>
        <p class="mt-2 text-sm opacity-70">
          {city_name(@lot.room)}<span :if={@lot.room.address}>, {@lot.room.address}</span>
        </p>
        <figure :if={@lot.room.entrance_photos != []} id="lot-entrance" class="mt-3">
          <div class="flex gap-2 overflow-x-auto">
            <a
              :for={key <- @lot.room.entrance_photos}
              href={Basa.Storage.url(key)}
              target="_blank"
              class="shrink-0"
            >
              <img
                src={Basa.Storage.url(key)}
                alt={gettext("The way in")}
                class="h-40 rounded-xl object-cover"
                loading="lazy"
              />
            </a>
          </div>
          <figcaption class="mt-1 text-sm">
            {gettext("The way in, photographed by the owner.")}
          </figcaption>
        </figure>
        <figure :if={@lot.room.street_view} id="lot-street-view" class="mt-3">
          <img
            src={Basa.Storage.url(@lot.room.street_view["key"])}
            alt={gettext("The street near the address")}
            class="max-h-64 w-full rounded-xl object-cover"
            loading="lazy"
          />
          <figcaption class="mt-1 space-y-0.5">
            <p class="text-sm">{gettext("The street near the address, not the room.")}</p>
            <.street_view_credit view={@lot.room.street_view} />
          </figcaption>
        </figure>
      </section>

      <section class="mt-6">
        <.page_title
          title={
            if @lot.deal == :sale, do: gettext("Pick a handover time"), else: gettext("Pick a time")
          }
          level={2}
        />
        <.widget
          id="lot-calendar"
          component="AvailabilityCalendar"
          props={calendar_props(assigns)}
          enabled={@widgets?}
        >
          <:loading>
            <div class="h-72 animate-pulse rounded-xl bg-zinc-100 dark:bg-zinc-800"></div>
          </:loading>
          <:fallback>
            <div class="-mx-1 flex gap-2 overflow-x-auto px-1 pb-2">
              <.button
                :for={d <- @days}
                phx-click="pick_date"
                phx-value-date={Date.to_iso8601(d)}
                size="small"
                rounded="large"
                variant={if d == @date, do: "default", else: "bordered"}
                color={if d == @date, do: "primary", else: "natural"}
                class="shrink-0"
              >
                <span class="flex flex-col leading-tight">
                  <span class="text-xs opacity-70">{BasaWeb.Dates.format(d, "%a")}</span>
                  <span>{Calendar.strftime(d, "%d.%m")}</span>
                </span>
              </.button>
            </div>
            <div id="slots" class="mt-3 grid grid-cols-3 gap-2 sm:grid-cols-6">
              <.button
                :for={s <- @slots}
                disabled={!s.free? or @own?}
                phx-click="pick_slot"
                phx-value-start={DateTime.to_iso8601(s.starts_at)}
                size="small"
                rounded="large"
                variant={if s.free?, do: "bordered", else: "subtle"}
                color={if s.free?, do: "success", else: "natural"}
                class={!s.free? && "line-through opacity-50"}
              >
                {if @lot.price_unit == :day,
                  do: gettext("Whole day"),
                  else: local_time(s.starts_at, @lot)}
              </.button>
            </div>
            <p :if={@slots == []} class="mt-2 text-sm opacity-70">{gettext("Closed on this day.")}</p>
          </:fallback>
        </.widget>
        <p class="mt-2 text-xs opacity-60">
          {gettext("Times are in %{tz}. Taken slots update live.", tz: @lot.timezone)}
        </p>
        <p :if={@own?} class="mt-2 text-sm">
          {gettext("This is your offer.")}
          <.link navigate={~p"/my/lots/#{@lot.id}/edit"} class="underline">{gettext("Edit it")}</.link>
        </p>
      </section>

      <.modal
        :if={@start}
        id="booking-dialog"
        show
        title={
          if @lot.deal == :sale,
            do: gettext("Buy %{title}", title: @lot.title),
            else: gettext("Book %{title}", title: @lot.title)
        }
        on_cancel={JS.push("close_dialog")}
        size="medium"
        rounded="large"
      >
        <p class="flex items-center gap-1.5">
          {gettext("Starts")} {local_datetime(@start, @lot)}
          <.info_tip :if={@lot.deal == :sale} id="handover-info">
            {gettext("You meet the seller at this time; the items become yours at the handover.")}
          </.info_tip>
        </p>
        <div :if={@lot.deal != :sale} class="mt-3 flex items-center gap-3">
          <span>{gettext("Duration")}</span>
          <.button_group rounded="large">
            <.button phx-click="units" phx-value-delta="-1" size="small" variant="bordered">−</.button>
            <.button size="small" variant="bordered" disabled>{@units} × {unit_label(@lot.price_unit)}</.button>
            <.button phx-click="units" phx-value-delta="1" size="small" variant="bordered">+</.button>
          </.button_group>
        </div>

        <%= case @quote do %>
          <% {:ok, q} -> %>
            <p class="mt-3">{gettext("Until")} {local_datetime(q.ends_at, @lot)}</p>
            <p class="mt-1 text-xl font-bold">{Basa.Money.format(q.price, @lot.currency)}</p>
          <% {:error, _field, message} -> %>
            <p class="mt-3 text-rose-600 dark:text-rose-400">{message}</p>
          <% _ -> %>
        <% end %>

        <.alert :if={@booking_error} kind={:danger} class="mt-3" rounded="large">
          {@booking_error}
        </.alert>

        <%= if @current_user do %>
          <form phx-submit="book" class="mt-4 space-y-3">
            <.textarea_field
              name="note"
              placeholder={gettext("Message to the lessor (optional)")}
              rows="2"
            />
            <p class="text-xs opacity-70">
              {if @lot.booking_mode == :instant,
                do: gettext("Instant booking: confirmed at once."),
                else: gettext("The lessor confirms your request; the slot is held meanwhile.")}
              {gettext("Free cancellation up to %{h} h before.", h: @lot.cancellation_hours)}
            </p>
            <div class="flex justify-end gap-2">
              <.button type="button" variant="transparent" phx-click="close_dialog">{gettext("Cancel")}</.button>
              <.button
                type="submit"
                color="primary"
                variant="default"
                disabled={not match?({:ok, _}, @quote)}
              >
                {if @lot.deal == :sale, do: gettext("Buy"), else: gettext("Book")}
              </.button>
            </div>
          </form>
        <% else %>
          <div class="mt-4 flex justify-end gap-2">
            <.button type="button" variant="transparent" phx-click="close_dialog">{gettext("Cancel")}</.button>
            <.button_link href={~p"/sign-in"} color="primary" variant="default">{gettext(
              "Sign in to book"
            )}</.button_link>
          </div>
        <% end %>
      </.modal>
    </Layouts.app>
    """
  end

  def role_label(:sound_engineer), do: gettext("Sound engineer")
  def role_label(:assistant), do: gettext("Assistant")
  def role_label(:guide), do: gettext("Guide")
  def role_label(:key_holder), do: gettext("Key holder")
  def role_label(:specialist), do: gettext("Specialist")
  def role_label(_), do: gettext("Attendant")
end
