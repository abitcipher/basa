defmodule BasaWeb.HomeLive do
  use BasaWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: gettext("Find a studio, gear or tools"),
       near: Basa.System.settings()
     )}
  end

  @sorts ~w(recommended price_asc price_desc newest)

  @impl true
  def handle_params(params, _uri, socket) do
    filters = %{
      "q" => blank(params["q"]),
      "city" => blank(params["city"]),
      "type" => blank(params["type"]),
      "deal" => if(params["deal"] in ~w(lease sale), do: params["deal"]),
      "date" => date(params["date"]),
      "price_max" => int(params["price_max"]),
      "currency" => currency(params["currency"]),
      "mobile" => params["mobile"] == "true",
      "sort" => if(params["sort"] in @sorts, do: params["sort"], else: "recommended"),
      "view" => if(params["view"] == "map", do: "map", else: "list"),
      "lat" => float(params["lat"]),
      "lng" => float(params["lng"]),
      "radius" =>
        if(params["radius"] in Basa.System.near_steps(socket.assigns.near),
          do: params["radius"]
        )
    }

    city = city(filters["city"])
    filters = Map.put(filters, "city", city && city.id)
    radius = filters["radius"] || radius(filters, socket.assigns.near)

    {:noreply,
     assign(socket,
       filters: filters,
       city: city,
       radius: radius,
       lots: search(filters, city, radius, socket.assigns.current_user)
     )}
  end

  defp radius(%{"lat" => lat}, near) when is_float(lat), do: near.near_default

  defp radius(%{"city" => id}, near) when is_binary(id),
    do: if("city" in Basa.System.near_steps(near), do: "city", else: near.near_default)

  defp radius(_filters, _near), do: nil

  defp city(nil), do: nil
  defp city(value), do: Basa.Geo.get(value) || Basa.Geo.find_by_name(value)

  @impl true
  def handle_event("search", %{"filters" => f}, socket) do
    params =
      socket.assigns.filters
      |> Map.merge(Map.take(f, ~w(q type date price_max currency sort radius)))
      |> Map.merge(radius_from_slider(f, socket.assigns.near))
      |> Map.put("mobile", f["mobile"] == "true")

    {:noreply, push_patch(socket, to: ~p"/?#{query(params, socket)}")}
  end

  def handle_event("view", %{"view" => view}, socket) do
    {:noreply,
     push_patch(socket, to: ~p"/?#{query(Map.put(socket.assigns.filters, "view", view), socket)}")}
  end

  def handle_event("open_lot", %{"id" => id}, socket),
    do: {:noreply, push_navigate(socket, to: ~p"/lots/#{id}")}

  def handle_event("clear_filters", _, socket),
    do:
      {:noreply,
       push_patch(socket,
         to: ~p"/?#{query(%{"view" => socket.assigns.filters["view"]}, socket)}"
       )}

  defp radius_from_slider(%{"radius_step" => i}, near) do
    case Enum.at(Basa.System.near_steps(near), int(i) || -1) do
      nil -> %{}
      step -> %{"radius" => step}
    end
  end

  defp radius_from_slider(_, _), do: %{}

  @impl true
  def handle_info({BasaWeb.CityPicker, "filters-city", {:located, city, lat, lng}}, socket),
    do: where(socket, %{"city" => city.id, "lat" => lat, "lng" => lng})

  def handle_info({BasaWeb.CityPicker, "filters-city", nil}, socket),
    do: where(socket, %{"city" => nil, "lat" => nil, "lng" => nil, "radius" => nil})

  def handle_info({BasaWeb.CityPicker, "filters-city", city}, socket),
    do: where(socket, %{"city" => city.id, "lat" => nil, "lng" => nil})

  defp where(socket, changes) do
    params = Map.merge(socket.assigns.filters, changes)
    {:noreply, push_patch(socket, to: ~p"/?#{query(params, socket)}")}
  end

  defp sort_options do
    [
      {"recommended", gettext("Recommended")},
      {"price_asc", gettext("Cheapest first")},
      {"price_desc", gettext("Most expensive first")},
      {"newest", gettext("Newest")}
    ]
  end

  defp default_currency(nil), do: :UAH
  defp default_currency(city), do: Basa.Geo.Countries.currency(city.country_code)

  defp search(f, city, radius, actor) do
    args =
      %{
        q: f["q"],
        free_on: f["date"],
        mobile: f["mobile"],
        sort: String.to_existing_atom(f["sort"])
      }
      |> Map.merge(
        if f["type"], do: %{service_type: String.to_existing_atom(f["type"])}, else: %{}
      )
      |> Map.merge(if f["deal"], do: %{deal: String.to_existing_atom(f["deal"])}, else: %{})
      |> Map.merge(
        if f["price_max"] && f["currency"],
          do: %{price_max: f["price_max"], currency: f["currency"]},
          else: %{}
      )

    args
    |> Map.merge(where_args(f, city, radius))
    |> Basa.Search.find_lots(actor: actor, limit: 50)
  end

  @defaults %{"sort" => "recommended", "view" => "list", "mobile" => false}

  defp query(params, socket) do
    defaults = Map.put(@defaults, "radius", radius(params, socket.assigns.near))

    params
    |> Enum.reject(fn {k, v} -> v in [nil, ""] or defaults[k] == v end)
    |> Map.new(fn {k, v} -> {k, to_string(v)} end)
  end

  defp extra_filters(f),
    do: Enum.count([f["date"], f["price_max"], f["mobile"], f["sort"] != "recommended"], & &1)

  defp filtered?(f),
    do: Enum.any?(~w(q city type date price_max lat), &f[&1]) or f["mobile"]

  defp date(v) do
    case v && Date.from_iso8601(v) do
      {:ok, d} -> d
      _ -> nil
    end
  end

  defp currency(v) do
    Enum.find(Basa.Money.currencies(), &(to_string(&1) == v))
  end

  defp markers(lots) do
    lots
    |> Enum.filter(&(&1.room && &1.room.lat))
    |> Enum.map(fn lot ->
      %{
        id: lot.id,
        lat: lot.room.lat,
        lng: lot.room.lng,
        title: lot.title,
        price: price_text(lot),
        featured: lot.featured
      }
    end)
  end

  defp where_args(_f, nil, _radius), do: %{}
  defp where_args(_f, city, "city"), do: %{city_id: city.id}

  defp where_args(_f, city, "region"),
    do: %{region_country: city.country_code, region_admin1: city.admin1}

  defp where_args(f, city, km) do
    {lat, lng} = if f["lat"], do: {f["lat"], f["lng"]}, else: {city.lat, city.lng}
    %{lat: lat, lng: lng, radius_km: int(km)}
  end

  defp blank(v) when v in [nil, ""], do: nil
  defp blank(v), do: v

  defp float(nil), do: nil
  defp float(v) when is_number(v), do: v * 1.0

  defp float(v),
    do:
      (case Float.parse(v) do
         {f, _} -> f
         :error -> nil
       end)

  defp int(nil), do: nil

  defp int(v),
    do:
      (case Integer.parse(to_string(v)) do
         {i, _} -> i
         :error -> nil
       end)

  attr :control, :atom, required: true
  attr :steps, :list, required: true
  attr :value, :string, required: true
  attr :city, :any, required: true
  attr :located, :boolean, required: true

  defp radius_control(assigns) do
    assigns =
      assign(assigns,
        index: Enum.find_index(assigns.steps, &(&1 == assigns.value)) || 0,
        now: radius_label(assigns.value, assigns.city, assigns.located)
      )

    ~H"""
    <div id="near-radius" class="flex items-center gap-2">
      <%= case @control do %>
        <% :slider -> %>
          <div class="relative w-56 sm:w-64">
            <input
              type="range"
              id="near-radius-slider"
              name="filters[radius_step]"
              min="0"
              max={length(@steps) - 1}
              step="1"
              value={@index}
              phx-debounce="300"
              aria-label={gettext("How far")}
              aria-valuetext={@now}
              class="block w-full accent-[var(--ui-action)]"
            />
            <div
              class="absolute inset-x-0 top-full flex justify-between text-[10px] opacity-60"
              aria-hidden="true"
            >
              <span :for={step <- @steps}>{radius_short(step)}</span>
            </div>
          </div>
        <% :chips -> %>
          <fieldset class="flex flex-wrap items-center gap-1">
            <legend class="sr-only">{gettext("How far")}</legend>
            <label :for={step <- @steps} class="cursor-pointer">
              <input
                type="radio"
                name="filters[radius]"
                value={step}
                checked={step == @value}
                class="peer sr-only"
              />
              <span class="block rounded-full border border-zinc-300 px-2.5 py-1 text-xs peer-checked:border-transparent peer-checked:bg-[var(--ui-action)] peer-checked:text-white peer-focus-visible:ring-2 dark:border-zinc-700">
                {radius_short(step)}
              </span>
            </label>
          </fieldset>
        <% :select -> %>
          <.native_select
            id="near-radius-select"
            name="filters[radius]"
            size="small"
            rounded="large"
            class="w-auto"
            aria-label={gettext("How far")}
          >
            <:option :for={step <- @steps} value={step} selected={step == @value}>
              {radius_short(step)}
            </:option>
          </.native_select>
      <% end %>
      <.info_tip id="near-radius-info" align="end">
        <span class="block">
          {gettext(
            "How far to search: from your location, or from the city's centre. Or the whole city, or its whole region."
          )}
        </span>
        <span id="near-radius-now" class="mt-1 block font-medium">{@now}</span>
      </.info_tip>
    </div>
    """
  end

  defp radius_label("city", city, _), do: gettext("Whole city: %{city}", city: place_name(city))

  defp radius_label("region", city, _),
    do: gettext("Whole region around %{city}", city: place_name(city))

  defp radius_label(km, _city, true), do: gettext("Within %{km} km of you", km: km)

  defp radius_label(km, city, false),
    do: gettext("Within %{km} km of %{city}", km: km, city: place_name(city))

  defp place_name(city), do: Basa.Geo.City.display_name(city, Gettext.get_locale(BasaWeb.Gettext))

  defp radius_short("city"), do: gettext("City")
  defp radius_short("region"), do: gettext("Region")
  defp radius_short(km), do: gettext("%{km} km", km: km)

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} unread={@unread_count} active={:find}>
      <section class="mb-6">
        <h1 class="text-2xl font-bold sm:text-3xl">{gettext("Needed nearby")}</h1>
        <p class="opacity-70">
          {gettext(
            "Recording studios, music gear, tools and outfits: rent by the hour or day, or buy."
          )}
        </p>
      </section>

      <.form
        for={%{}}
        as={:filters}
        id="search-form"
        phx-submit="search"
        phx-change="search"
        class="space-y-3"
      >
        <.search_field
          name="filters[q]"
          value={@filters["q"]}
          placeholder={gettext("Studio, microphone, drill…")}
          phx-debounce="400"
          size="large"
          rounded="large"
        />
        <div class="flex flex-wrap items-center gap-x-4 gap-y-2 has-[#near-radius-slider]:pb-3">
          <div class="w-full sm:w-72">
            <.live_component
              module={BasaWeb.CityPicker}
              id="filters-city"
              name="filters[city]"
              city={@city}
              mode={:service}
              point
              located={is_float(@filters["lat"])}
              clearable
              placeholder={gettext("Any city")}
            />
          </div>
          <.radius_control
            :if={@radius && @city}
            control={@near.near_control}
            steps={Basa.System.near_steps(@near)}
            value={@radius}
            city={@city}
            located={is_float(@filters["lat"])}
          />
        </div>
        <div class="flex flex-wrap items-center gap-2">
          <.native_select
            id="filters-deal"
            name="filters[deal]"
            size="small"
            rounded="large"
            class="w-auto"
          >
            <:option value="">{gettext("Rent or buy")}</:option>
            <:option value="lease" selected={@filters["deal"] == "lease"}>{gettext("Rent")}</:option>
            <:option value="sale" selected={@filters["deal"] == "sale"}>{gettext("Buy")}</:option>
          </.native_select>
          <.native_select
            id="filters-type"
            name="filters[type]"
            size="small"
            rounded="large"
            class="w-auto"
          >
            <:option value="">{gettext("Anything")}</:option>
            <:option value="venue_rental" selected={@filters["type"] == "venue_rental"}>
              {gettext("Venues")}
            </:option>
            <:option value="equipment_rental" selected={@filters["type"] == "equipment_rental"}>
              {gettext("Equipment")}
            </:option>
            <:option value="person_time" selected={@filters["type"] == "person_time"}>
              {gettext("Specialists")}
            </:option>
            <:option value="mixed" selected={@filters["type"] == "mixed"}>
              {gettext("Bundles")}
            </:option>
          </.native_select>
        </div>

        <.button
          type="button"
          id="toggle-filters"
          size="small"
          variant="bordered"
          rounded="large"
          icon="hero-adjustments-horizontal"
          class="sm:hidden"
          phx-click={JS.toggle_class("max-sm:hidden", to: "#more-filters")}
        >
          {gettext("Filters")}
          <span
            :if={extra_filters(@filters) > 0}
            class="ml-1 rounded-full bg-primary-light px-1.5 text-xs text-white"
          >
            {extra_filters(@filters)}
          </span>
        </.button>
        <div
          id="more-filters"
          class={["flex flex-wrap items-end gap-3", extra_filters(@filters) == 0 && "max-sm:hidden"]}
        >
          <div class="w-40">
            <.date_time_field
              id="filters-date"
              name="filters[date]"
              type="date"
              value={@filters["date"] && Date.to_iso8601(@filters["date"])}
              min={Date.to_iso8601(Date.utc_today())}
              label={gettext("Free on")}
              label_class="text-sm"
              size="small"
              rounded="large"
            />
          </div>
          <div class="flex items-end gap-1">
            <div class="w-28">
              <.number_field
                id="filters-price-max"
                name="filters[price_max]"
                value={@filters["price_max"]}
                min="0"
                step="1"
                label={gettext("Up to")}
                label_class="text-sm"
                size="small"
                rounded="large"
                phx-debounce="500"
              />
            </div>
            <.native_select
              id="filters-currency"
              name="filters[currency]"
              size="small"
              rounded="large"
              class="w-auto"
            >
              <:option
                :for={c <- Basa.Money.currencies()}
                value={c}
                selected={(@filters["currency"] || default_currency(@city)) == c}
              >
                {c}
              </:option>
            </.native_select>
          </div>
          <.native_select
            id="filters-sort"
            name="filters[sort]"
            label={gettext("Sort")}
            size="small"
            rounded="large"
            class="w-auto"
          >
            <:option
              :for={{value, label} <- sort_options()}
              value={value}
              selected={@filters["sort"] == value}
            >
              {label}
            </:option>
          </.native_select>
          <label class="flex cursor-pointer items-center gap-2 pb-2 text-sm">
            <input type="hidden" name="filters[mobile]" value="false" />
            <input
              id="filters-mobile"
              type="checkbox"
              name="filters[mobile]"
              value="true"
              checked={@filters["mobile"]}
              class="size-4 rounded"
            />
            {gettext("Comes to you")}
          </label>
          <.button
            :if={filtered?(@filters)}
            type="button"
            phx-click="clear_filters"
            variant="transparent"
            size="small"
            class="pb-2"
          >
            {gettext("Clear filters")}
          </.button>
        </div>
      </.form>

      <div class="mt-6 flex items-center justify-between gap-3">
        <p id="results-count" class="text-sm opacity-70">
          {ngettext("1 offer", "%{count} offers", length(@lots))}
        </p>
        <.button_group rounded="large">
          <.button
            :for={
              {view, label, icon} <- [
                {"list", gettext("List"), "hero-list-bullet"},
                {"map", gettext("Map"), "hero-map"}
              ]
            }
            id={"view-#{view}"}
            type="button"
            phx-click="view"
            phx-value-view={view}
            size="small"
            icon={icon}
            variant={if @filters["view"] == view, do: "default", else: "bordered"}
            color={if @filters["view"] == view, do: "primary", else: "natural"}
          >
            {label}
          </.button>
        </.button_group>
      </div>

      <section :if={@filters["view"] == "map" and @lots != []} class="mt-3">
        <div
          id="results-map"
          phx-hook="ResultsMap"
          phx-update="ignore"
          data-markers={Jason.encode!(markers(@lots))}
          data-open-label={gettext("Open")}
          class="relative z-0 h-[60vh] overflow-hidden rounded-xl bg-zinc-100 dark:bg-zinc-800"
        >
        </div>
      </section>

      <section :if={@filters["view"] == "list"} class="mt-3 space-y-3">
        <.lot_card :for={lot <- @lots} lot={lot} />
      </section>

      <.empty_state
        :if={@lots == []}
        title={gettext("Nothing found yet")}
        icon="hero-magnifying-glass"
        class="mt-3"
      >
        {if filtered?(@filters),
          do: gettext("Try fewer filters, another day or a shorter search."),
          else: gettext("Try another city or a shorter search.")}
        <:action>
          <.button_link navigate={~p"/my/lots/new"} variant="bordered" size="small">
            {gettext("List your own studio or gear")}
          </.button_link>
        </:action>
      </.empty_state>
    </Layouts.app>
    """
  end

  defp price_text(%{deal: :sale} = lot), do: Basa.Money.format(lot.price_amount, lot.currency)

  defp price_text(lot),
    do: "#{Basa.Money.format(lot.price_amount, lot.currency)} / #{unit_label(lot.price_unit)}"
end
