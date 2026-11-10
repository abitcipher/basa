defmodule BasaWeb.My.LotWizardLive do
  use BasaWeb, :live_view

  alias Basa.Catalog
  alias BasaWeb.KeepState

  @days ~w(1 2 3 4 5 6 7)

  @impl true
  def mount(params, _session, socket) do
    actor = socket.assigns.current_user
    baskets = Catalog.list_my_baskets!(actor: actor)
    rooms = Catalog.list_my_rooms!(actor: actor, load: [:geo_city])

    {lot, draft} =
      case params do
        %{"id" => id} ->
          lot = Catalog.get_lot!(id, actor: actor)
          {lot, from_lot(lot)}

        _ ->
          {nil, new_draft(baskets, rooms)}
      end

    {:ok,
     socket
     |> assign(
       page_title: gettext("Offer"),
       lot: lot,
       draft: draft,
       step: 0,
       errors: [],
       baskets: baskets,
       rooms: rooms
     )
     |> KeepState.start("lot-wizard:" <> ((lot && lot.id) || "new"), draft)}
  end

  defp room_city(room) do
    case Basa.Geo.get(room.city_id) do
      nil -> nil
      city -> %{timezone: city.timezone, currency: Basa.Geo.Countries.currency(city.country_code)}
    end
  end

  defp new_draft(baskets, rooms) do
    room = List.first(rooms)
    city = room && room_city(room)
    basket = List.first(baskets)

    %{
      "basket_id" => basket && basket.id,
      "room_id" => room && room.id,
      "title" => (basket && basket.title) || "",
      "description" => "",
      "deal" => "lease",
      "price_unit" => "hour",
      "slot_minutes" => 120,
      "days" => MapSet.new(~w(1 2 3 4 5 6)),
      "from" => "10:00",
      "to" => "22:00",
      "timezone" => (city && city.timezone) || "Europe/Kyiv",
      "currency" => to_string((city && city.currency) || :UAH),
      "price_amount" => suggested_price(basket, "hour"),
      "booking_mode" => "instant",
      "min_units" => 1,
      "buffer_minutes" => 0,
      "lead_time_hours" => 2,
      "cancellation_hours" => 24
    }
  end

  defp from_lot(lot) do
    {days, from, to} =
      case lot.weekly_hours do
        hours when map_size(hours) > 0 ->
          [[f, t] | _] = hours |> Map.values() |> hd()
          {MapSet.new(Map.keys(hours)), f, t}

        _ ->
          {MapSet.new(~w(1 2 3 4 5 6 7)), "00:00", "24:00"}
      end

    %{
      "basket_id" => lot.basket_id,
      "room_id" => lot.room_id,
      "title" => lot.title,
      "description" => lot.description || "",
      "deal" => to_string(lot.deal),
      "price_unit" => to_string(lot.price_unit),
      "slot_minutes" => lot.slot_minutes || 120,
      "days" => days,
      "from" => from,
      "to" => to,
      "timezone" => lot.timezone,
      "currency" => to_string(lot.currency),
      "price_amount" => Decimal.to_integer(Decimal.round(lot.price_amount)),
      "booking_mode" => to_string(lot.booking_mode),
      "min_units" => lot.min_units,
      "buffer_minutes" => lot.buffer_minutes,
      "lead_time_hours" => lot.lead_time_hours,
      "cancellation_hours" => lot.cancellation_hours
    }
  end

  defp sale_price(nil), do: 1000

  defp sale_price(basket) do
    value =
      basket.items
      |> Enum.map(&(&1.estimated_value || Decimal.new(0)))
      |> Enum.reduce(Decimal.new(0), &Decimal.add/2)

    if Decimal.compare(value, 0) == :gt, do: Decimal.to_integer(Decimal.round(value)), else: 1000
  end

  defp suggested_price(nil, _), do: 300

  defp suggested_price(basket, unit) do
    value =
      basket.items
      |> Enum.map(&(&1.estimated_value || Decimal.new(0)))
      |> Enum.reduce(Decimal.new(0), &Decimal.add/2)

    if Decimal.compare(value, 0) == :gt do
      daily = Basa.Money.suggested_daily_rate(value)

      case unit do
        "day" -> Decimal.to_integer(daily)
        "hour" -> max(1, div(Decimal.to_integer(daily), 8))
        "slot" -> max(1, div(Decimal.to_integer(daily), 4))
      end
    else
      300
    end
  end

  @impl true
  def handle_event("change", %{"lot" => params}, socket) do
    {:noreply, assign(socket, draft: merge(socket.assigns.draft, params))}
  end

  def handle_event("pick", %{"field" => field, "id" => id}, socket)
      when field in ["basket_id", "room_id"] do
    draft = Map.put(socket.assigns.draft, field, id)

    draft =
      case field do
        "basket_id" ->
          basket = Enum.find(socket.assigns.baskets, &(&1.id == id))

          draft
          |> Map.put("title", if(draft["title"] == "", do: basket.title, else: draft["title"]))
          |> Map.put("price_amount", suggested_price(basket, draft["price_unit"]))

        "room_id" ->
          room = Enum.find(socket.assigns.rooms, &(&1.id == id))

          case room_city(room) do
            nil ->
              draft

            city ->
              Map.merge(draft, %{
                "timezone" => city.timezone,
                "currency" => to_string(city.currency)
              })
          end
      end

    {:noreply, assign(socket, draft: draft)}
  end

  def handle_event("noop", _, socket), do: {:noreply, socket}

  def handle_event("pick_deal", %{"deal" => deal}, socket) when deal in ~w(lease sale) do
    basket = Enum.find(socket.assigns.baskets, &(&1.id == socket.assigns.draft["basket_id"]))

    {:noreply,
     update(socket, :draft, fn d ->
       d
       |> Map.put("deal", deal)
       |> Map.put("price_unit", "hour")
       |> Map.put(
         "price_amount",
         if(deal == "sale", do: sale_price(basket), else: suggested_price(basket, "hour"))
       )
     end)}
  end

  def handle_event("pick_unit", %{"unit" => unit}, socket) when unit in ~w(hour slot day) do
    {:noreply, update(socket, :draft, &Map.put(&1, "price_unit", unit))}
  end

  def handle_event("toggle_day", %{"day" => day}, socket) do
    days = socket.assigns.draft["days"]
    days = if MapSet.member?(days, day), do: MapSet.delete(days, day), else: MapSet.put(days, day)
    {:noreply, update(socket, :draft, &Map.put(&1, "days", days))}
  end

  def handle_event("price_step", %{"delta" => delta}, socket) do
    {:noreply,
     update(
       socket,
       :draft,
       &Map.update!(&1, "price_amount", fn p -> max(0, p + String.to_integer(delta)) end)
     )}
  end

  def handle_event("use_suggestion", _, socket) do
    basket = Enum.find(socket.assigns.baskets, &(&1.id == socket.assigns.draft["basket_id"]))

    {:noreply,
     update(
       socket,
       :draft,
       &Map.put(&1, "price_amount", suggested_price(basket, &1["price_unit"]))
     )}
  end

  def handle_event("keep:restore", %{"token" => token}, socket) do
    case KeepState.restore(socket, token) do
      {:ok, {step, draft}} -> {:reply, %{ok: true}, assign(socket, step: step, draft: draft)}
      :error -> {:reply, %{ok: false}, socket}
    end
  end

  def handle_event("goto", %{"step" => step}, socket) do
    step = String.to_integer(step)
    d = socket.assigns.draft

    cond do
      step > 0 and (is_nil(d["basket_id"]) or is_nil(d["room_id"])) ->
        {:noreply, assign(socket, errors: [gettext("Pick a basket and a room.")])}

      step > 1 and MapSet.size(d["days"]) == 0 and d["price_unit"] != "day" ->
        {:noreply, assign(socket, errors: [gettext("Pick at least one day.")])}

      true ->
        {:noreply, assign(socket, step: step, errors: [])}
    end
  end

  def handle_event("save", %{"publish" => publish}, socket) do
    %{draft: d, lot: lot, current_user: actor} = socket.assigns
    attrs = to_attrs(d)

    result =
      if lot,
        do: Catalog.update_lot(lot, attrs, actor: actor),
        else: Catalog.create_lot(attrs, actor: actor)

    with {:ok, saved} <- result,
         {:ok, saved} <- maybe_submit(saved, publish == "true", actor) do
      message =
        case saved.state do
          :published ->
            gettext("Your offer is live.")

          :under_review ->
            gettext("Sent for review. We'll let you know.")

          :draft when publish == "true" ->
            gettext("Saved as draft. See the notes on your dashboard.")

          _ ->
            gettext("Saved.")
        end

      {:noreply,
       socket |> KeepState.forget() |> put_flash(:info, message) |> push_navigate(to: ~p"/my")}
    else
      {:error, error} -> {:noreply, assign(socket, errors: BasaWeb.ErrorText.messages(error))}
    end
  end

  defp maybe_submit(%{state: :draft} = lot, true, actor),
    do: Catalog.submit_lot(lot, actor: actor)

  defp maybe_submit(lot, _, _), do: {:ok, lot}

  defp to_attrs(d) do
    hours =
      if d["price_unit"] == "day",
        do: %{},
        else: Map.new(d["days"], &{&1, [[d["from"], d["to"]]]})

    %{
      basket_id: d["basket_id"],
      room_id: d["room_id"],
      title: d["title"],
      description: d["description"],
      deal: String.to_existing_atom(d["deal"]),
      price_unit: String.to_existing_atom(d["price_unit"]),
      slot_minutes: if(d["price_unit"] == "slot", do: d["slot_minutes"]),
      weekly_hours: hours,
      timezone: d["timezone"],
      currency: String.to_existing_atom(d["currency"]),
      price_amount: d["price_amount"],
      booking_mode: String.to_existing_atom(d["booking_mode"]),
      min_units: d["min_units"],
      buffer_minutes: d["buffer_minutes"],
      lead_time_hours: d["lead_time_hours"],
      cancellation_hours: d["cancellation_hours"]
    }
  end

  @ints ~w(slot_minutes price_amount min_units buffer_minutes lead_time_hours cancellation_hours)

  defp merge(draft, params) do
    params
    |> Map.take(~w(title description price_unit from to timezone currency booking_mode) ++ @ints)
    |> Map.new(fn
      {k, v} when k in @ints -> {k, parse_int(v, draft[k])}
      kv -> kv
    end)
    |> then(&Map.merge(draft, &1))
  end

  defp parse_int(v, default) do
    case Integer.parse(to_string(v)) do
      {i, _} -> i
      :error -> default
    end
  end

  defp times,
    do:
      for(
        h <- 0..24,
        do: if(h == 24, do: "24:00", else: String.pad_leading("#{h}", 2, "0") <> ":00")
      )

  @impl true
  def render(assigns) do
    assigns =
      assign(assigns,
        days: Enum.map(@days, &{&1, BasaWeb.Dates.weekday_short(String.to_integer(&1))}),
        basket: Enum.find(assigns.baskets, &(&1.id == assigns.draft["basket_id"])),
        room: Enum.find(assigns.rooms, &(&1.id == assigns.draft["room_id"]))
      )

    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} unread={@unread_count} active={:my}>
      <KeepState.kept keep={@keep} data={{@step, @draft}} />
      <.page_title title={if @lot, do: gettext("Edit offer"), else: gettext("New offer")} />
      <.wizard_steps
        steps={[gettext("What & where"), gettext("When"), gettext("Price"), gettext("Publish")]}
        current={@step}
      />
      <.alert :if={@errors != []} kind={:danger} rounded="large" class="mb-4">
        <ul>
          <li :for={e <- @errors}>{e}</li>
        </ul>
      </.alert>

      <form id="lot-form" phx-change="change" phx-submit="noop" class="space-y-4">
        <div :if={@step == 0} class="space-y-4">
          <section>
            <.page_title title={gettext("Basket")} level={2} />
            <div class="grid gap-2 sm:grid-cols-2">
              <.select_card
                :for={b <- @baskets}
                selected={b.id == @draft["basket_id"]}
                phx-click="pick"
                phx-value-field="basket_id"
                phx-value-id={b.id}
              >
                <div class="p-3">
                  <p class="font-medium">{b.title}</p>
                  <p class="line-clamp-1 text-xs opacity-70">
                    {Enum.map_join(b.items, ", ", & &1.title)}
                  </p>
                </div>
              </.select_card>
            </div>
            <.empty_state :if={@baskets == []} title={gettext("No baskets yet")}>
              <:action>
                <.button_link navigate={~p"/my/baskets/new"} size="small" variant="bordered">{gettext(
                  "Create a basket"
                )}</.button_link>
              </:action>
            </.empty_state>
          </section>

          <section>
            <.page_title title={gettext("Room")} level={2} />
            <div class="grid gap-2 sm:grid-cols-2">
              <.select_card
                :for={r <- @rooms}
                selected={r.id == @draft["room_id"]}
                phx-click="pick"
                phx-value-field="room_id"
                phx-value-id={r.id}
              >
                <div class="p-3">
                  <p class="font-medium">{r.title}</p>
                  <p class="text-xs opacity-70">
                    {city_name(r)} {if r.mobile, do: "· " <> gettext("mobile")}
                  </p>
                </div>
              </.select_card>
            </div>
            <.empty_state :if={@rooms == []} title={gettext("No rooms yet")}>
              <:action>
                <.button_link navigate={~p"/my/rooms/new"} size="small" variant="bordered">{gettext(
                  "Add a room"
                )}</.button_link>
              </:action>
            </.empty_state>
          </section>

          <.text_field
            name="lot[title]"
            value={@draft["title"]}
            label={gettext("Offer title")}
            size="medium"
          />
          <.textarea_field
            name="lot[description]"
            value={@draft["description"]}
            label={gettext("Description")}
            rows="3"
          />
        </div>

        <div :if={@step == 1} class="space-y-4">
          <div>
            <p class="mb-2 flex items-center gap-1.5 text-sm font-medium">
              {gettext("Offer")}
              <.info_tip :if={@draft["deal"] == "sale"} id="sale-info">
                {gettext(
                  "Buyers book a one-hour handover within the hours below. When the buyer confirms delivery, the items are marked sold and taken off all your offers."
                )}
              </.info_tip>
            </p>
            <.choice_buttons
              options={[{"lease", gettext("Rent out")}, {"sale", gettext("Sell")}]}
              selected={@draft["deal"]}
              event="pick_deal"
              key="deal"
              cols="grid-cols-2"
            />
          </div>
          <div :if={@draft["deal"] != "sale"}>
            <p class="mb-2 text-sm font-medium">{gettext("Rented by")}</p>
            <.choice_buttons
              options={[
                {"hour", gettext("Hour")},
                {"slot", gettext("Fixed slot")},
                {"day", gettext("Day")}
              ]}
              selected={@draft["price_unit"]}
              event="pick_unit"
              key="unit"
              cols="grid-cols-3"
            />
          </div>
          <.native_select
            :if={@draft["price_unit"] == "slot" and @draft["deal"] != "sale"}
            id="lot-slot-minutes"
            name="lot[slot_minutes]"
            label={gettext("Slot length")}
            size="medium"
          >
            <:option
              :for={m <- [60, 90, 120, 180, 240, 360]}
              value={m}
              selected={@draft["slot_minutes"] == m}
            >
              {gettext("%{h} h", h: m / 60)}
            </:option>
          </.native_select>
          <div :if={@draft["price_unit"] != "day"} class="space-y-3">
            <p class="text-sm font-medium">{gettext("Open on")}</p>
            <div class="flex flex-wrap gap-1">
              <.button
                :for={{d, label} <- @days}
                type="button"
                phx-click="toggle_day"
                phx-value-day={d}
                size="small"
                class="w-14"
                variant={if MapSet.member?(@draft["days"], d), do: "default", else: "bordered"}
                color={if MapSet.member?(@draft["days"], d), do: "primary", else: "natural"}
              >
                {label}
              </.button>
            </div>
            <div class="flex items-end gap-2">
              <.native_select id="lot-from" name="lot[from]" label={gettext("From")} size="small">
                <:option :for={t <- times()} value={t} selected={@draft["from"] == t}>{t}</:option>
              </.native_select>
              <.native_select id="lot-to" name="lot[to]" label={gettext("To")} size="small">
                <:option :for={t <- times()} value={t} selected={@draft["to"] == t}>{t}</:option>
              </.native_select>
            </div>
          </div>
          <p class="text-xs opacity-60">{gettext("Local time: %{tz}", tz: @draft["timezone"])}</p>
        </div>

        <div :if={@step == 2} class="space-y-4">
          <div class="text-center">
            <p class="text-4xl font-bold">
              {@draft["price_amount"]} <span class="text-lg">{@draft["currency"]}</span>
              <.info_tip id="price-info" align="end" class="text-base font-normal">
                {gettext(
                  "Suggested from the basket's market value. You can change the price any time, even after publishing."
                )}
              </.info_tip>
            </p>
            <p :if={@draft["deal"] != "sale"} class="opacity-70">
              / {unit_label(String.to_existing_atom(@draft["price_unit"]))}
            </p>
            <p :if={@draft["deal"] == "sale"} class="opacity-70">{gettext("For sale")}</p>
          </div>
          <.range_field
            name="lot[price_amount]"
            value={@draft["price_amount"]}
            min="0"
            max={max(@draft["price_amount"] * 3, 1000)}
            size="medium"
          />
          <div class="flex flex-wrap justify-center gap-2">
            <.button
              type="button"
              size="small"
              variant="bordered"
              phx-click="price_step"
              phx-value-delta="-50"
            >−50</.button>
            <.button
              type="button"
              size="small"
              variant="bordered"
              phx-click="price_step"
              phx-value-delta="-10"
            >−10</.button>
            <.button
              type="button"
              size="small"
              color="secondary"
              variant="default"
              phx-click="use_suggestion"
            >{gettext("Suggested")}</.button>
            <.button
              type="button"
              size="small"
              variant="bordered"
              phx-click="price_step"
              phx-value-delta="10"
            >+10</.button>
            <.button
              type="button"
              size="small"
              variant="bordered"
              phx-click="price_step"
              phx-value-delta="50"
            >+50</.button>
          </div>

          <div class="grid grid-cols-2 gap-3">
            <.native_select
              id="lot-currency"
              name="lot[currency]"
              label={gettext("Currency")}
              size="medium"
            >
              <:option
                :for={c <- Basa.Money.currencies()}
                value={c}
                selected={@draft["currency"] == to_string(c)}
              >
                {c}
              </:option>
            </.native_select>
            <.native_select
              id="lot-booking-mode"
              name="lot[booking_mode]"
              label={gettext("Booking")}
              size="medium"
            >
              <:option value="instant" selected={@draft["booking_mode"] == "instant"}>
                {gettext("Instant")}
              </:option>
              <:option value="request" selected={@draft["booking_mode"] == "request"}>
                {gettext("On request")}
              </:option>
            </.native_select>
            <.number_field
              name="lot[min_units]"
              value={@draft["min_units"]}
              min="1"
              label={gettext("Minimum units")}
              size="medium"
            />
            <.number_field
              name="lot[buffer_minutes]"
              value={@draft["buffer_minutes"]}
              min="0"
              label={gettext("Break between bookings, min")}
              size="medium"
            />
            <.number_field
              name="lot[lead_time_hours]"
              value={@draft["lead_time_hours"]}
              min="0"
              label={gettext("Book at least, h ahead")}
              size="medium"
            />
            <.number_field
              name="lot[cancellation_hours]"
              value={@draft["cancellation_hours"]}
              min="0"
              label={gettext("Free cancellation, h before")}
              size="medium"
            />
          </div>
        </div>

        <.card :if={@step == 3} padding="medium" rounded="large" class="space-y-1">
          <h2 class="text-lg font-semibold">{@draft["title"]}</h2>
          <p>{@basket && @basket.title} · {@room && "#{@room.title}, #{city_name(@room)}"}</p>
          <p>
            {@draft["price_amount"]} {@draft["currency"]} / {unit_label(
              String.to_existing_atom(@draft["price_unit"])
            )} · {if @draft["booking_mode"] == "instant",
              do: gettext("instant booking"),
              else: gettext("on request")}
          </p>
          <p :if={@draft["price_unit"] != "day"} class="text-sm opacity-80">
            {@days
            |> Enum.filter(fn {d, _} -> MapSet.member?(@draft["days"], d) end)
            |> Enum.map_join(" ", &elem(&1, 1))} · {@draft["from"]}–{@draft["to"]}
          </p>
        </.card>
      </form>

      <div class="mt-6 flex justify-between gap-2">
        <.button :if={@step > 0} variant="transparent" phx-click="goto" phx-value-step={@step - 1}>{gettext(
          "Back"
        )}</.button>
        <span :if={@step == 0}></span>
        <.button
          :if={@step < 3}
          color="primary"
          variant="default"
          phx-click="goto"
          phx-value-step={@step + 1}
        >{gettext("Next")}</.button>
        <div :if={@step == 3} class="flex gap-2">
          <.button
            :if={is_nil(@lot) or @lot.state == :draft}
            variant="bordered"
            phx-click="save"
            phx-value-publish="false"
          >
            {gettext("Save draft")}
          </.button>
          <.button
            color="primary"
            variant="default"
            phx-click="save"
            phx-value-publish="true"
            phx-disable-with={gettext("Publishing…")}
          >
            {if @lot && @lot.state == :published,
              do: gettext("Save changes"),
              else: gettext("Publish")}
          </.button>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def handle_info(_msg, socket), do: {:noreply, socket}
end
