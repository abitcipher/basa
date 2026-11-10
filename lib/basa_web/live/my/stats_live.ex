defmodule BasaWeb.My.StatsLive do
  use BasaWeb, :live_view

  alias Basa.Bookings.LessorStats
  alias BasaWeb.WidgetEvents

  @days 30

  @impl true
  def mount(_params, _session, socket) do
    actor = socket.assigns.current_user
    if connected?(socket), do: Basa.Events.subscribe_availability(actor.id)
    to = Date.utc_today()

    {:ok,
     socket
     |> assign(page_title: gettext("Stats"), from: Date.add(to, -(@days - 1)), to: to)
     |> load()}
  end

  @impl true
  def handle_info({event, _owner_id}, socket)
      when event in [:availability_changed, :bookings_changed] do
    socket =
      if socket.assigns.widgets?,
        do: WidgetEvents.push(socket, "lessor-stats", "LessorStats", "bookings.changed"),
        else: load(socket)

    {:noreply, socket}
  end

  def handle_info(_other, socket), do: {:noreply, socket}

  defp load(%{assigns: %{widgets?: true}} = socket), do: socket

  defp load(socket) do
    %{current_user: actor, from: from, to: to} = socket.assigns
    assign(socket, stats: LessorStats.compute(actor, from, to))
  end

  defp props(assigns) do
    %{
      locale: Gettext.get_locale(BasaWeb.Gettext),
      from: Date.to_iso8601(assigns.from),
      to: Date.to_iso8601(assigns.to),
      labels: %{
        occupancy: gettext("Occupancy"),
        perWeek: gettext("Per week"),
        earnings: gettext("Earnings"),
        bookings: gettext("Bookings"),
        error: gettext("Couldn't load the stats."),
        retry: gettext("Try again"),
        empty: gettext("No offers yet")
      }
    }
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} unread={@unread_count} active={:my} wide>
      <.page_title title={gettext("Stats")} />
      <p class="mb-4 text-sm opacity-70">
        {gettext("Confirmed and completed bookings, %{from}–%{to}.",
          from: Calendar.strftime(@from, "%d.%m"),
          to: Calendar.strftime(@to, "%d.%m.%Y")
        )}
      </p>

      <.widget id="lessor-stats" component="LessorStats" props={props(assigns)} enabled={@widgets?}>
        <:loading>
          <div class="h-80 animate-pulse rounded-xl bg-zinc-100 dark:bg-zinc-800"></div>
        </:loading>
        <:fallback>
          <p :if={@stats.offers == []} class="text-sm opacity-70">{gettext("No offers yet")}</p>
          <div :if={@stats.offers != []} class="grid gap-6 lg:grid-cols-2">
            <section>
              <h2 class="mb-2 font-semibold">{gettext("Occupancy")}</h2>
              <table id="stats-offers" class="w-full text-sm">
                <tbody>
                  <tr :for={o <- @stats.offers} class="border-b border-zinc-200 dark:border-zinc-800">
                    <td class="py-2">{o.title}</td>
                    <td class="py-2 text-right">{o.booked_hours} / {o.open_hours} h</td>
                    <td class="py-2 text-right font-semibold">{o.occupancy}%</td>
                    <td class="py-2 text-right">{Basa.Money.format(o.earnings, o.currency)}</td>
                  </tr>
                </tbody>
              </table>
            </section>
            <section>
              <h2 class="mb-2 font-semibold">{gettext("Per week")}</h2>
              <table id="stats-weeks" class="w-full text-sm">
                <thead>
                  <tr class="text-left opacity-60">
                    <th class="py-1 font-normal"></th>
                    <th class="py-1 text-right font-normal">{gettext("Bookings")}</th>
                    <th class="py-1 text-right font-normal">{gettext("Earnings")}</th>
                  </tr>
                </thead>
                <tbody>
                  <tr :for={w <- @stats.weeks} class="border-b border-zinc-200 dark:border-zinc-800">
                    <td class="py-2">{Calendar.strftime(w.week, "%d.%m")}</td>
                    <td class="py-2 text-right">{w.bookings}</td>
                    <td class="py-2 text-right">{Basa.Money.format(w.earnings, @stats.currency)}</td>
                  </tr>
                </tbody>
              </table>
            </section>
          </div>
        </:fallback>
      </.widget>
    </Layouts.app>
    """
  end
end
