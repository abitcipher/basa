defmodule BasaWeb.Admin.DataLive do
  use BasaWeb, :live_view

  @kinds ~w(users bookings payments)
  @fallback_rows 50

  @impl true
  def mount(_params, _session, socket) do
    if socket.assigns.current_user.role == :admin do
      {:ok, assign(socket, page_title: gettext("Data"))}
    else
      {:ok, socket |> put_flash(:error, gettext("Admins only.")) |> push_navigate(to: ~p"/")}
    end
  end

  @impl true
  def handle_params(params, _uri, socket) do
    kind = if params["kind"] in @kinds, do: params["kind"], else: "users"
    {:noreply, socket |> assign(kind: kind) |> load()}
  end

  defp load(%{assigns: %{widgets?: true}} = socket), do: socket

  defp load(socket) do
    actor = socket.assigns.current_user

    {resource, load} =
      case socket.assigns.kind do
        "users" -> {Basa.Accounts.User, [:bookings_count]}
        "bookings" -> {Basa.Bookings.Booking, [:lot_title, :lessor_name, :lessee_name]}
        "payments" -> {Basa.Payments.Payment, [:user_name, :lot_title]}
      end

    rows =
      resource
      |> Ash.Query.for_read(:admin_list, %{}, actor: actor)
      |> Ash.Query.load(load)
      |> Ash.Query.limit(@fallback_rows)
      |> Ash.read!()

    assign(socket, rows: rows)
  end

  defp labels do
    %{
      displayName: gettext("Name"),
      email: gettext("Email"),
      telegramUsername: "Telegram",
      locale: gettext("Language"),
      bookingsCount: gettext("Bookings"),
      startsAt: gettext("Starts"),
      lotTitle: gettext("Offer"),
      lessorName: gettext("Lessor"),
      lesseeName: gettext("Lessee"),
      status: gettext("Status"),
      priceAmount: gettext("Price"),
      paidAt: gettext("Paid"),
      purpose: gettext("Purpose"),
      userName: gettext("User"),
      amount: gettext("Amount"),
      export: gettext("Export CSV"),
      error: gettext("Couldn't load the data."),
      status_pending: state_label(:pending),
      status_confirmed: state_label(:confirmed),
      status_completed: state_label(:completed),
      status_declined: state_label(:declined),
      status_cancelled: state_label(:cancelled)
    }
  end

  defp kind_label("users"), do: gettext("Users")
  defp kind_label("bookings"), do: gettext("Bookings")
  defp kind_label("payments"), do: gettext("Payments")

  defp when_text(nil), do: ""
  defp when_text(dt), do: Calendar.strftime(dt, "%d.%m.%Y %H:%M")

  @impl true
  def render(assigns) do
    assigns = assign(assigns, kinds: @kinds)

    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} unread={@unread_count} wide>
      <.page_title title={gettext("Data")} />

      <div class="mb-3 flex flex-wrap gap-2">
        <.button_link
          :for={k <- @kinds}
          id={"kind-#{k}"}
          patch={~p"/admin/data?#{%{kind: k}}"}
          size="small"
          variant={if @kind == k, do: "default", else: "bordered"}
          color={if @kind == k, do: "primary", else: "natural"}
        >
          {kind_label(k)}
        </.button_link>
      </div>

      <.widget
        id={"admin-grid-#{@kind}"}
        component="AdminGrid"
        props={%{kind: @kind, locale: Gettext.get_locale(BasaWeb.Gettext), labels: labels()}}
        enabled={@widgets?}
      >
        <:loading>
          <div class="h-[70vh] animate-pulse rounded-xl bg-zinc-100 dark:bg-zinc-800"></div>
        </:loading>
        <:fallback>
          <div class="overflow-x-auto">
            <table id="admin-table" class="w-full text-sm">
              <tbody :if={@kind == "users"}>
                <tr :for={u <- @rows} class="border-b border-zinc-200 dark:border-zinc-800">
                  <td class="py-2">{u.display_name}</td>
                  <td class="py-2">{u.email}</td>
                  <td class="py-2">{u.telegram_username}</td>
                  <td class="py-2">{u.locale}</td>
                  <td class="py-2 text-right">{u.bookings_count}</td>
                </tr>
              </tbody>
              <tbody :if={@kind == "bookings"}>
                <tr :for={b <- @rows} class="border-b border-zinc-200 dark:border-zinc-800">
                  <td class="py-2">{when_text(b.starts_at)}</td>
                  <td class="py-2">{b.lot_title}</td>
                  <td class="py-2">{b.lessor_name}</td>
                  <td class="py-2">{b.lessee_name}</td>
                  <td class="py-2"><.state_badge state={b.status} /></td>
                  <td class="py-2 text-right">{Basa.Money.format(b.price_amount, b.currency)}</td>
                </tr>
              </tbody>
              <tbody :if={@kind == "payments"}>
                <tr :for={p <- @rows} class="border-b border-zinc-200 dark:border-zinc-800">
                  <td class="py-2">{when_text(p.paid_at)}</td>
                  <td class="py-2">{p.purpose}</td>
                  <td class="py-2">{p.user_name}</td>
                  <td class="py-2">{p.lot_title}</td>
                  <td class="py-2">{p.status}</td>
                  <td class="py-2 text-right">{Basa.Money.format(p.amount, p.currency)}</td>
                </tr>
              </tbody>
            </table>
          </div>
        </:fallback>
      </.widget>
    </Layouts.app>
    """
  end
end
