defmodule BasaWeb.BookingsLive do
  use BasaWeb, :live_view

  require Ash.Query

  alias Basa.Bookings

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    if connected?(socket),
      do: Phoenix.PubSub.subscribe(Basa.PubSub, Basa.Events.user_topic(user.id))

    {:ok,
     socket
     |> assign(page_title: gettext("Bookings"), tab: "mine", support: nil, support_amount: 0)
     |> load()}
  end

  @impl true
  def handle_params(%{"tab" => tab}, _uri, socket) when tab in ["mine", "incoming"],
    do: {:noreply, assign(socket, tab: tab)}

  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  @impl true
  def handle_event("act", %{"id" => id, "action" => action}, socket) do
    actor = socket.assigns.current_user

    result =
      with {:ok, booking} <- Bookings.get_booking(id, actor: actor) do
        case action do
          "cancel" -> Bookings.cancel_booking(booking, actor: actor)
          "confirm" -> Bookings.confirm_booking(booking, actor: actor)
          "decline" -> Bookings.decline_booking(booking, actor: actor)
          "complete" -> Bookings.complete_booking(booking, actor: actor)
        end
      end

    socket =
      case result do
        {:ok, _} -> put_flash(socket, :info, gettext("Done."))
        {:error, %{errors: [%{message: m} | _]}} -> put_flash(socket, :error, m)
        {:error, _} -> put_flash(socket, :error, gettext("That didn't work. Please try again."))
      end

    {:noreply, load(socket)}
  end

  def handle_event("support", %{"id" => id}, socket) do
    booking = Enum.find(socket.assigns.incoming, &(&1.id == id))
    suggested = Basa.Payments.Products.suggested_commission(booking.price_amount)
    {:noreply, assign(socket, support: booking, support_amount: Decimal.to_integer(suggested))}
  end

  def handle_event("support_amount", %{"amount" => amount}, socket) do
    {:noreply, assign(socket, support_amount: String.to_integer(amount))}
  end

  def handle_event("close_support", _, socket), do: {:noreply, assign(socket, support: nil)}

  def handle_event("pay_support", _, socket) do
    %{support: booking, support_amount: amount, current_user: user} = socket.assigns

    case Basa.Payments.start_commission(booking.id, amount, actor: user) do
      {:ok, payment} ->
        {:noreply, redirect(socket, external: payment.payment_url)}

      {:error, error} ->
        {:noreply,
         socket
         |> assign(support: nil)
         |> put_flash(:error, Enum.join(BasaWeb.ErrorText.messages(error), " "))}
    end
  end

  def handle_event("contract", %{"id" => id}, socket) do
    case Map.get(socket.assigns.contracts, id) ||
           Basa.Witness.open_transaction(id, %{}, actor: socket.assigns.current_user) do
      %Basa.Witness.Transaction{} = tx ->
        {:noreply, push_navigate(socket, to: ~p"/transactions/#{tx.id}")}

      {:ok, tx} ->
        {:noreply, push_navigate(socket, to: ~p"/transactions/#{tx.id}")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("That didn't work. Please try again."))}
    end
  end

  @impl true
  def handle_info({:booking_event, _event, _id}, socket), do: {:noreply, load(socket)}
  def handle_info({:payment_settled, _id}, socket), do: {:noreply, load(socket)}

  defp load(socket) do
    actor = socket.assigns.current_user

    supported =
      Basa.Payments.list_my_payments!(actor: actor)
      |> Enum.filter(&(&1.purpose == :commission and &1.status == :succeeded))
      |> MapSet.new(& &1.booking_id)

    mine = Bookings.list_my_bookings!(actor: actor)
    incoming = Bookings.list_incoming_bookings!(actor: actor)

    assign(socket,
      mine: mine,
      incoming: incoming,
      supported: supported,
      payments?: Basa.Payments.enabled?(),
      contracts: contracts(mine ++ incoming)
    )
  end

  defp contracts(bookings) do
    ids = Enum.map(bookings, & &1.id)

    Basa.Witness.Transaction
    |> Ash.Query.filter(booking_id in ^ids and status != :cancelled)
    |> Ash.read!(authorize?: false)
    |> Map.new(&{&1.booking_id, &1})
  end

  defp when_text(b) do
    tz = b.lot.timezone
    s = DateTime.shift_zone!(b.starts_at, tz)
    e = DateTime.shift_zone!(b.ends_at, tz)
    "#{BasaWeb.Dates.format(s, "%a %d.%m %H:%M")}–#{Calendar.strftime(e, "%H:%M")}"
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} unread={@unread_count} active={:bookings}>
      <.page_title title={gettext("Bookings")} help="finding-and-booking" />

      <.button_group rounded="large" class="mb-4">
        <.button_link
          patch={~p"/bookings?tab=mine"}
          size="small"
          variant={if @tab == "mine", do: "default", else: "bordered"}
          color={if @tab == "mine", do: "primary", else: "natural"}
        >
          {gettext("I booked")} ({length(@mine)})
        </.button_link>
        <.button_link
          patch={~p"/bookings?tab=incoming"}
          size="small"
          variant={if @tab == "incoming", do: "default", else: "bordered"}
          color={if @tab == "incoming", do: "primary", else: "natural"}
        >
          {gettext("For my offers")} ({length(@incoming)})
        </.button_link>
      </.button_group>

      <div class="space-y-3">
        <.card
          :for={b <- if(@tab == "mine", do: @mine, else: @incoming)}
          padding="medium"
          rounded="large"
        >
          <div class="flex justify-between gap-2">
            <.link navigate={~p"/lots/#{b.lot_id}"} class="font-semibold hover:underline">{b.lot.title}</.link>
            <.state_badge state={b.status} />
          </div>
          <p class="text-sm">{when_text(b)} · {city_name(b.lot.room)}</p>
          <p class="text-sm opacity-70">
            {Basa.Money.format(b.price_amount, b.currency)}
            <span :if={@tab == "incoming"}> · {Layouts.display_name(b.lessee)}</span>
          </p>
          <p :if={b.note} class="text-sm italic opacity-80">“{b.note}”</p>

          <div class="mt-3 flex flex-wrap justify-end gap-2">
            <%= if @tab == "incoming" do %>
              <.button
                :if={b.status == :pending}
                size="small"
                color="primary"
                variant="default"
                phx-click="act"
                phx-value-id={b.id}
                phx-value-action="confirm"
              >
                {gettext("Confirm")}
              </.button>
              <.button
                :if={b.status == :pending}
                size="small"
                variant="bordered"
                phx-click="act"
                phx-value-id={b.id}
                phx-value-action="decline"
              >
                {gettext("Decline")}
              </.button>
              <.button
                :if={b.status == :completed and @payments? and not MapSet.member?(@supported, b.id)}
                size="small"
                color="secondary"
                variant="default"
                icon="hero-heart"
                phx-click="support"
                phx-value-id={b.id}
              >
                {gettext("Support BASA")}
              </.button>
              <span :if={MapSet.member?(@supported, b.id)} class="text-sm opacity-70">
                {gettext("Thanks for supporting BASA")}
              </span>
              <.button
                :if={b.status == :confirmed}
                size="small"
                variant="bordered"
                phx-click="act"
                phx-value-id={b.id}
                phx-value-action="complete"
              >
                {gettext("Mark as done")}
              </.button>
            <% end %>
            <.button
              :if={b.status == :confirmed or Map.has_key?(@contracts, b.id)}
              id={"contract-#{b.id}"}
              size="small"
              color="primary"
              variant="bordered"
              icon="hero-document-text"
              phx-click="contract"
              phx-value-id={b.id}
            >
              {if Map.has_key?(@contracts, b.id),
                do: gettext("Contract"),
                else: gettext("Make a contract")}
            </.button>
            <.button
              :if={b.status in [:pending, :confirmed]}
              size="small"
              variant="transparent"
              color="danger"
              phx-click="act"
              phx-value-id={b.id}
              phx-value-action="cancel"
              data-confirm={gettext("Cancel this booking?")}
            >
              {gettext("Cancel booking")}
            </.button>
          </div>
        </.card>

        <.empty_state
          :if={@tab == "mine" and @mine == []}
          title={gettext("No bookings yet")}
          icon="hero-calendar"
        >
          <:action>
            <.button_link navigate={~p"/"} size="small" color="primary" variant="default">{gettext(
              "Find something to book"
            )}</.button_link>
          </:action>
        </.empty_state>
        <.empty_state
          :if={@tab == "incoming" and @incoming == []}
          title={gettext("No requests yet")}
          icon="hero-inbox"
        >
          {gettext("When someone books your offer, it shows up here.")}
        </.empty_state>
      </div>

      <.modal
        :if={@support}
        id="support-dialog"
        show
        title={gettext("Support BASA")}
        on_cancel={JS.push("close_support")}
        rounded="large"
      >
        <p class="text-sm opacity-80">
          {gettext(
            "BASA is free to use. If this booking went well, you can share a part of it with us. It's voluntary."
          )}
        </p>
        <form id="support-form" phx-change="support_amount" class="mt-4">
          <p class="text-center text-3xl font-bold">{@support_amount} {@support.currency}</p>
          <.range_field
            name="amount"
            value={@support_amount}
            min="1"
            max={Decimal.to_integer(Decimal.round(@support.price_amount, 0, :down))}
            size="medium"
          />
          <p class="text-center text-xs opacity-60">
            {gettext("Suggested: %{amount} (5% of the booking)",
              amount: Basa.Payments.Products.suggested_commission(@support.price_amount)
            )}
          </p>
        </form>
        <div class="mt-4 flex justify-end gap-2">
          <.button variant="transparent" phx-click="close_support">{gettext("Not now")}</.button>
          <.button
            color="primary"
            variant="default"
            phx-click="pay_support"
            phx-disable-with={gettext("Opening payment…")}
          >
            {gettext("Pay %{amount} %{currency}",
              amount: @support_amount,
              currency: @support.currency
            )}
          </.button>
        </div>
      </.modal>
    </Layouts.app>
    """
  end
end
