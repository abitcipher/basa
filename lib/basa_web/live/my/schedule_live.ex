defmodule BasaWeb.My.ScheduleLive do
  use BasaWeb, :live_view

  alias Basa.Bookings
  alias Basa.Bookings.LessorSchedule
  alias BasaWeb.WidgetEvents

  @list_days 14
  @board_back 14
  @board_ahead 60
  @views ~w(calendar resources requests)

  @impl true
  def mount(_params, _session, socket) do
    actor = socket.assigns.current_user
    if connected?(socket), do: Basa.Events.subscribe_availability(actor.id)

    {:ok,
     socket
     |> assign(page_title: gettext("Schedule"), opened: nil, timezone: timezone(actor))
     |> load()}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    view = if params["view"] in @views, do: params["view"], else: "calendar"
    {:noreply, assign(socket, view: view)}
  end

  @impl true
  def handle_event("widget:event", packet, socket),
    do: WidgetEvents.handle(packet, socket, &widget_event/4)

  def handle_event("open_booking", %{"id" => id}, socket), do: {:noreply, open(socket, id)}

  def handle_event("close_booking", _, socket), do: {:noreply, assign(socket, opened: nil)}

  def handle_event("act", %{"action" => action}, socket),
    do: {:noreply, act(socket, socket.assigns.opened, action)}

  @impl true
  def handle_info({event, _owner_id}, socket)
      when event in [:availability_changed, :bookings_changed],
      do: {:noreply, changed(socket)}

  def handle_info(_other, socket), do: {:noreply, socket}

  defp widget_event(_widget, "booking.opened", %{"bookingId" => id}, socket),
    do: {:noreply, open(socket, id)}

  defp widget_event(_widget, "booking.moved", %{"bookingId" => id, "to" => column}, socket) do
    case own_booking(socket, id) do
      nil ->
        {:noreply, changed(socket)}

      booking ->
        case move(booking.status, column) do
          nil ->
            {:noreply,
             socket |> put_flash(:error, gettext("This move isn't possible.")) |> changed()}

          action ->
            {:noreply, act(socket, booking, action)}
        end
    end
  end

  defp widget_event(_widget, _type, _data, socket), do: {:noreply, socket}

  def move(:pending, "confirmed"), do: "confirm"
  def move(:pending, "closed"), do: "decline"
  def move(:confirmed, "completed"), do: "complete"
  def move(:confirmed, "closed"), do: "cancel"
  def move(_status, _column), do: nil

  defp act(socket, booking, action) do
    actor = socket.assigns.current_user

    result =
      case action do
        "confirm" -> Bookings.confirm_booking(booking, actor: actor)
        "decline" -> Bookings.decline_booking(booking, actor: actor)
        "complete" -> Bookings.complete_booking(booking, actor: actor)
        "cancel" -> Bookings.cancel_booking(booking, actor: actor)
      end

    case result do
      {:ok, booking} ->
        socket
        |> put_flash(:info, gettext("Done."))
        |> then(&if(&1.assigns.opened, do: open(&1, booking.id), else: &1))
        |> changed()

      {:error, error} ->
        socket
        |> put_flash(:error, Enum.join(BasaWeb.ErrorText.messages(error), "; "))
        |> changed()
    end
  end

  defp changed(%{assigns: %{widgets?: true}} = socket) do
    socket
    |> WidgetEvents.push("schedule-calendar", "LessorCalendar", "bookings.changed")
    |> WidgetEvents.push("schedule-resources", "ResourceTimeline", "bookings.changed")
    |> WidgetEvents.push("schedule-requests", "BookingBoard", "bookings.changed")
  end

  defp changed(socket), do: load(socket)

  defp load(%{assigns: %{widgets?: true}} = socket), do: socket

  defp load(socket) do
    actor = socket.assigns.current_user
    today = Date.utc_today()
    to = Date.add(today, @list_days - 1)

    assign(socket,
      days:
        actor
        |> LessorSchedule.bookings(today, to)
        |> Enum.group_by(&local_date(&1.starts_at, &1.timezone))
        |> Enum.filter(fn {date, _} -> Date.compare(date, today) != :lt end)
        |> Enum.sort_by(&elem(&1, 0), Date),
      resources:
        actor
        |> LessorSchedule.resources(today, to)
        |> Enum.filter(&(&1.bookings != []))
    )
    |> assign(
      requests:
        actor
        |> LessorSchedule.bookings(Date.add(today, -@board_back), Date.add(today, @board_ahead))
        |> Enum.group_by(& &1.status)
    )
  end

  defp open(socket, id) do
    case own_booking(socket, id) do
      nil -> socket
      booking -> assign(socket, opened: booking)
    end
  end

  defp own_booking(socket, id) do
    case Bookings.get_booking(id,
           actor: socket.assigns.current_user,
           load: [:lessee, lot: [:room]]
         ) do
      {:ok, %{owner_id: owner} = booking} when owner == socket.assigns.current_user.id ->
        booking

      _ ->
        nil
    end
  end

  defp timezone(actor) do
    case Basa.Catalog.list_my_lots(actor: actor) do
      {:ok, [_ | _] = lots} ->
        lots |> Enum.frequencies_by(& &1.timezone) |> Enum.max_by(&elem(&1, 1)) |> elem(0)

      _ ->
        "Europe/Kyiv"
    end
  end

  defp local_date(dt, tz), do: dt |> DateTime.shift_zone!(tz) |> DateTime.to_date()

  defp local_time(dt, tz), do: dt |> DateTime.shift_zone!(tz) |> Calendar.strftime("%H:%M")

  defp calendar_props do
    %{
      locale: Gettext.get_locale(BasaWeb.Gettext),
      labels: %{
        error: gettext("Couldn't load the schedule."),
        retry: gettext("Try again"),
        pending: gettext("Waiting for you"),
        confirmed: gettext("Confirmed"),
        completed: gettext("Done")
      }
    }
  end

  defp timeline_props(timezone) do
    %{
      locale: Gettext.get_locale(BasaWeb.Gettext),
      timezone: timezone,
      labels: %{
        resource: gettext("Room, gear or person"),
        room: gettext("Room"),
        item: gettext("Item"),
        attendant: gettext("Person"),
        rooms: gettext("Rooms"),
        items: gettext("Gear"),
        people: gettext("People"),
        day: gettext("Day"),
        week: gettext("Week"),
        month: gettext("Month"),
        today: gettext("Today"),
        previous: gettext("Earlier"),
        next: gettext("Later"),
        now: gettext("Now"),
        legend: gettext("Colours"),
        pending: gettext("Waiting for you"),
        confirmed: gettext("Confirmed"),
        completed: gettext("Done"),
        empty: gettext("Nothing to show yet: add rooms, gear or people to your offers."),
        error: gettext("Couldn't load the schedule."),
        retry: gettext("Try again")
      }
    }
  end

  defp board_props do
    %{
      locale: Gettext.get_locale(BasaWeb.Gettext),
      labels: %{
        pending: gettext("Waiting for you"),
        confirmed: gettext("Confirmed"),
        completed: gettext("Done"),
        closed: gettext("Declined or cancelled"),
        empty: gettext("No bookings in the coming weeks."),
        error: gettext("Couldn't load the schedule."),
        retry: gettext("Try again")
      }
    }
  end

  defp resource_label(:room), do: gettext("Room")
  defp resource_label(:item), do: gettext("Item")
  defp resource_label(:attendant), do: gettext("Person")

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} unread={@unread_count} active={:my} wide>
      <.page_title title={gettext("Schedule")} help="schedule" />

      <div class="mb-3 flex flex-wrap gap-2">
        <.button_link
          :for={
            {view, label, icon} <- [
              {"calendar", gettext("Calendar"), "hero-calendar-days"},
              {"resources", gettext("By room and gear"), "hero-queue-list"},
              {"requests", gettext("Requests"), "hero-view-columns"}
            ]
          }
          id={"view-#{view}"}
          patch={~p"/my/schedule?#{%{view: view}}"}
          size="small"
          icon={icon}
          variant={if @view == view, do: "default", else: "bordered"}
          color={if @view == view, do: "primary", else: "natural"}
        >
          {label}
        </.button_link>
      </div>

      <.widget
        :if={@view == "calendar"}
        id="schedule-calendar"
        component="LessorCalendar"
        props={calendar_props()}
        enabled={@widgets?}
      >
        <:loading>
          <div class="h-[70vh] animate-pulse rounded-xl bg-zinc-100 dark:bg-zinc-800"></div>
        </:loading>
        <:fallback>
          <p :if={@days == []} class="text-sm opacity-70">
            {gettext("No bookings in the coming weeks.")}
          </p>
          <section :for={{date, bookings} <- @days} class="mb-4">
            <h2 class="mb-2 font-semibold">{BasaWeb.Dates.format(date, "%A, %d.%m")}</h2>
            <div class="space-y-2">
              <button
                :for={b <- bookings}
                type="button"
                phx-click="open_booking"
                phx-value-id={b.id}
                class="flex w-full items-center justify-between gap-3 rounded-xl border border-zinc-200 p-3 text-left hover:bg-zinc-50 dark:border-zinc-800 dark:hover:bg-zinc-900"
              >
                <span>
                  <span class="font-medium">
                    {local_time(b.starts_at, b.timezone)}–{local_time(b.ends_at, b.timezone)}
                  </span>
                  {b.lot_title}<span :if={b.lessee} class="opacity-70"> · {b.lessee}</span>
                </span>
                <.state_badge state={b.status} />
              </button>
            </div>
          </section>
        </:fallback>
      </.widget>

      <.widget
        :if={@view == "resources"}
        id="schedule-resources"
        component="ResourceTimeline"
        props={timeline_props(@timezone)}
        enabled={@widgets?}
      >
        <:loading>
          <div class="h-[60vh] animate-pulse rounded-xl bg-zinc-100 dark:bg-zinc-800"></div>
        </:loading>
        <:fallback>
          <p :if={@resources == []} class="text-sm opacity-70">
            {gettext("No bookings in the coming weeks.")}
          </p>
          <section :for={r <- @resources} class="mb-4">
            <h2 class="mb-2 font-semibold">
              <span class="text-sm font-normal opacity-60">{resource_label(r.type)}:</span> {r.title}
            </h2>
            <div class="space-y-1">
              <button
                :for={b <- r.bookings}
                type="button"
                phx-click="open_booking"
                phx-value-id={b.booking_id}
                class="flex w-full items-center justify-between gap-3 rounded-lg px-3 py-2 text-left text-sm hover:bg-zinc-50 dark:hover:bg-zinc-900"
              >
                <span>
                  {BasaWeb.Dates.format(local_date(b.starts_at, @timezone), "%d.%m")}
                  {local_time(b.starts_at, @timezone)}–{local_time(b.ends_at, @timezone)} · {b.lot_title}
                </span>
                <.state_badge state={b.status} />
              </button>
            </div>
          </section>
        </:fallback>
      </.widget>

      <.widget
        :if={@view == "requests"}
        id="schedule-requests"
        component="BookingBoard"
        props={board_props()}
        enabled={@widgets?}
      >
        <:loading>
          <div class="h-[70vh] animate-pulse rounded-xl bg-zinc-100 dark:bg-zinc-800"></div>
        </:loading>
        <:fallback>
          <div class="grid gap-4 md:grid-cols-3">
            <section
              :for={
                {status, title} <- [
                  pending: gettext("Waiting for you"),
                  confirmed: gettext("Confirmed"),
                  completed: gettext("Done")
                ]
              }
              id={"requests-#{status}"}
            >
              <h2 class="mb-2 font-semibold">
                {title}
                <span class="text-sm font-normal opacity-60">{length(@requests[status] || [])}</span>
              </h2>
              <div class="space-y-2">
                <button
                  :for={b <- @requests[status] || []}
                  type="button"
                  phx-click="open_booking"
                  phx-value-id={b.id}
                  class="block w-full rounded-xl border border-zinc-200 p-3 text-left text-sm hover:bg-zinc-50 dark:border-zinc-800 dark:hover:bg-zinc-900"
                >
                  <span class="block font-medium">{b.lot_title}</span>
                  <span class="block opacity-80">
                    {BasaWeb.Dates.format(local_date(b.starts_at, b.timezone), "%a, %d.%m")}
                    {local_time(b.starts_at, b.timezone)}
                  </span>
                  <span :if={b.lessee} class="block text-xs opacity-70">{b.lessee}</span>
                </button>
              </div>
            </section>
          </div>
        </:fallback>
      </.widget>

      <.modal
        :if={@opened}
        id="booking-panel"
        show
        title={@opened.lot.title}
        on_cancel={JS.push("close_booking")}
        size="medium"
        rounded="large"
      >
        <div class="space-y-2 text-sm">
          <p><.state_badge state={@opened.status} /></p>
          <p>
            {BasaWeb.Dates.format(local_date(@opened.starts_at, @opened.lot.timezone), "%A, %d.%m")}
            {local_time(@opened.starts_at, @opened.lot.timezone)}–{local_time(
              @opened.ends_at,
              @opened.lot.timezone
            )}
            <span class="opacity-60">({@opened.lot.timezone})</span>
          </p>
          <p>{@opened.lot.room && @opened.lot.room.title}</p>
          <p>
            {Layouts.display_name(@opened.lessee)} · {Basa.Money.format(
              @opened.price_amount,
              @opened.currency
            )}
          </p>
          <p :if={@opened.note} class="italic opacity-80">“{@opened.note}”</p>
        </div>

        <div class="mt-4 flex flex-wrap justify-end gap-2">
          <.button
            :if={@opened.status == :pending}
            size="small"
            color="primary"
            variant="default"
            phx-click="act"
            phx-value-action="confirm"
          >
            {gettext("Confirm")}
          </.button>
          <.button
            :if={@opened.status == :pending}
            size="small"
            variant="bordered"
            phx-click="act"
            phx-value-action="decline"
          >
            {gettext("Decline")}
          </.button>
          <.button
            :if={@opened.status == :confirmed}
            size="small"
            variant="bordered"
            phx-click="act"
            phx-value-action="complete"
          >
            {gettext("Mark as done")}
          </.button>
          <.button
            :if={@opened.status in [:pending, :confirmed]}
            size="small"
            variant="transparent"
            color="danger"
            phx-click="act"
            phx-value-action="cancel"
            data-confirm={gettext("Cancel this booking?")}
          >
            {gettext("Cancel booking")}
          </.button>
        </div>
      </.modal>
    </Layouts.app>
    """
  end
end
