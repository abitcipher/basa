defmodule BasaWeb.CityPicker do
  use BasaWeb, :live_component

  alias Basa.Geo
  alias Basa.Geo.City

  @impl true
  def mount(socket) do
    {:ok,
     assign(socket,
       query: "",
       open?: false,
       results: [],
       candidates: [],
       miss: nil,
       popular?: false,
       note: nil,
       shown_city_id: :none
     )}
  end

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:mode, fn -> :service end)
      |> assign_new(:label, fn -> nil end)
      |> assign_new(:placeholder, fn -> gettext("Start typing a city") end)
      |> assign_new(:near_me, fn -> true end)
      |> assign_new(:point, fn -> false end)
      |> assign_new(:located, fn -> false end)
      |> assign_new(:clearable, fn -> false end)
      |> assign_new(:errors, fn -> [] end)
      |> assign_new(:city, fn -> nil end)

    city_id = socket.assigns.city && socket.assigns.city.id

    socket =
      if city_id != socket.assigns.shown_city_id,
        do: assign(socket, query: label(socket.assigns.city), shown_city_id: city_id),
        else: socket

    {:ok, socket}
  end

  @impl true
  def handle_event("type", params, socket) do
    q = params[input_name(socket.assigns.id)] || ""
    {:noreply, socket |> assign(query: q, open?: true, note: nil) |> search(q)}
  end

  def handle_event("open", _params, socket) do
    socket = assign(socket, open?: true)
    q = if socket.assigns.city, do: "", else: socket.assigns.query
    {:noreply, search(socket, q)}
  end

  def handle_event("close", _params, socket) do
    if socket.assigns.open?, do: record_miss(socket)
    query = if socket.assigns.city, do: label(socket.assigns.city), else: socket.assigns.query
    {:noreply, assign(socket, open?: false, query: query, miss: nil)}
  end

  def handle_event("pick", %{"id" => id}, socket) do
    case Enum.find(socket.assigns.results, &(&1.id == id)) do
      nil -> {:noreply, socket}
      city -> {:noreply, chosen(socket, city)}
    end
  end

  def handle_event("pick_external", %{"id" => id}, socket) do
    with %{} = cand <- Enum.find(socket.assigns.candidates, &(&1.id == id)),
         {:ok, city} <- Geo.add_candidate(cand, :lessor) do
      {:noreply, chosen(socket, city)}
    else
      _ -> {:noreply, assign(socket, note: gettext("Couldn't add this place. Try again."))}
    end
  end

  def handle_event("near", %{"lat" => lat, "lng" => lng}, socket) do
    case Geo.nearest(lat / 1, lng / 1) do
      nil ->
        {:noreply, socket}

      city when socket.assigns.point ->
        send(self(), {__MODULE__, socket.assigns.id, {:located, city, lat / 1, lng / 1}})
        {:noreply, shown(socket, city)}

      city ->
        {:noreply, chosen(socket, city)}
    end
  end

  def handle_event("geo_error", params, socket),
    do: {:noreply, assign(socket, note: geo_note(params["reason"], socket.assigns.city))}

  def handle_event("clear", _params, socket) do
    send(self(), {__MODULE__, socket.assigns.id, nil})
    {:noreply, assign(socket, city: nil, shown_city_id: nil, query: "", open?: false)}
  end

  defp search(socket, q) do
    q = String.trim(q)
    results = Geo.suggest(q, limit: 8)

    candidates =
      if socket.assigns.mode == :any and String.length(q) >= 3 and length(results) < 3,
        do: Geo.external(q, locale()),
        else: []

    miss = if results == [] and String.length(q) >= 3, do: q, else: nil
    assign(socket, results: results, candidates: candidates, miss: miss, popular?: q == "")
  end

  defp record_miss(%{assigns: %{mode: :service, miss: q}}) when is_binary(q),
    do: Geo.record_miss(q, locale())

  defp record_miss(_socket), do: :ok

  defp geo_note(reason, city), do: geo_reason(reason) <> " " <> geo_instead(city)

  defp geo_reason("denied"),
    do: gettext("Location is blocked for BASA: allow it in your browser's site settings.")

  defp geo_reason("insecure"), do: gettext("Location works only on a secure (https) page.")

  defp geo_reason(_),
    do: gettext("This device couldn't tell its location (location services may be off).")

  defp geo_instead(nil), do: gettext("Type the city instead.")
  defp geo_instead(_city), do: gettext("The search stays around the chosen city.")

  defp chosen(socket, city) do
    send(self(), {__MODULE__, socket.assigns.id, city})
    shown(socket, city)
  end

  defp shown(socket, city) do
    assign(socket,
      city: city,
      shown_city_id: city.id,
      query: label(city),
      open?: false,
      miss: nil,
      note: nil
    )
  end

  defp region(city, locale) do
    own = [city.name | Map.values(city.names || %{})] |> Enum.map(&String.downcase/1)
    admin1 = if city.admin1 && String.downcase(city.admin1) not in own, do: city.admin1

    [admin1, Basa.Geo.Countries.name(city.country_code, locale)]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(", ")
  end

  defp label(nil), do: ""
  defp label(%City{} = city), do: City.label(city, locale())

  defp locale, do: Gettext.get_locale(BasaWeb.Gettext)

  defp input_name(id), do: "#{id}_q"

  @impl true
  def render(assigns) do
    assigns =
      assign(assigns,
        input_name: input_name(assigns.id),
        listbox_id: "#{assigns.id}-list",
        locale: locale()
      )

    ~H"""
    <div
      id={@id}
      class="relative"
      phx-hook="CityPicker"
      phx-click-away={@open? && JS.push("close", target: @myself)}
      phx-window-keydown={@open? && JS.push("close", target: @myself)}
      phx-key="Escape"
    >
      <label :if={@label} for={"#{@id}-input"} class="mb-2 block font-semibold">
        {@label}
      </label>
      <input type="hidden" name={@name} value={@city && @city.id} />
      <div class="flex items-stretch gap-2">
        <div class="relative flex-1">
          <.icon
            name="hero-map-pin"
            class="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 opacity-50"
          />
          <input
            id={"#{@id}-input"}
            type="text"
            name={@input_name}
            value={@query}
            placeholder={@placeholder}
            autocomplete="off"
            role="combobox"
            aria-autocomplete="list"
            aria-expanded={to_string(@open?)}
            aria-controls={@listbox_id}
            phx-change="type"
            phx-focus="open"
            phx-target={@myself}
            phx-debounce="250"
            data-city-input
            class={[
              "w-full rounded-lg border bg-white py-2.5 pl-9 pr-9 text-sm outline-none transition",
              "border-zinc-300 focus:border-primary-light focus:ring-2 focus:ring-primary-light/20",
              "dark:border-zinc-700 dark:bg-zinc-900",
              @errors != [] && "border-rose-500"
            ]}
          />
          <button
            :if={@clearable and @city}
            type="button"
            phx-click="clear"
            phx-target={@myself}
            class="absolute right-2 top-1/2 -translate-y-1/2 rounded p-1 opacity-50 hover:opacity-100"
            aria-label={gettext("Clear")}
          >
            <.icon name="hero-x-mark" class="size-4" />
          </button>
        </div>
        <button
          :if={@near_me}
          id={"#{@id}-near-me"}
          type="button"
          data-near-me
          title={if @located, do: gettext("Searching around you"), else: gettext("Use my location")}
          aria-label={gettext("Use my location")}
          aria-pressed={to_string(@located)}
          class={[
            "shrink-0 rounded-lg border px-3 text-sm",
            if(@located,
              do: "border-transparent bg-[var(--ui-action)] text-white",
              else: "border-zinc-300 hover:bg-zinc-50 dark:border-zinc-700 dark:hover:bg-zinc-800"
            )
          ]}
        >
          <.icon name="hero-viewfinder-circle" class="size-5" />
        </button>
      </div>

      <div
        :if={@open?}
        id={@listbox_id}
        role="listbox"
        class="absolute z-30 mt-1 max-h-80 w-full overflow-auto rounded-xl border border-zinc-200 bg-white p-1 shadow-lg dark:border-zinc-700 dark:bg-zinc-900"
      >
        <p
          :if={@popular? and @results != []}
          class="px-3 pb-1 pt-2 text-xs opacity-50"
        >
          {gettext("Popular")}
        </p>
        <button
          :for={city <- @results}
          type="button"
          role="option"
          phx-click="pick"
          phx-value-id={city.id}
          phx-target={@myself}
          class={[
            "flex w-full items-baseline justify-between gap-3 rounded-lg px-3 py-2 text-left text-sm",
            "hover:bg-zinc-100 focus:bg-zinc-100 focus:outline-none dark:hover:bg-zinc-800 dark:focus:bg-zinc-800",
            @city && @city.id == city.id && "font-semibold"
          ]}
        >
          <span>{City.display_name(city, @locale)}</span>
          <span class="truncate text-xs opacity-60">
            {region(city, @locale)}
          </span>
        </button>

        <div :if={@candidates != []}>
          <p class="px-3 pb-1 pt-2 text-xs opacity-50">{gettext("More places (OpenStreetMap)")}</p>
          <button
            :for={cand <- @candidates}
            type="button"
            role="option"
            phx-click="pick_external"
            phx-value-id={cand.id}
            phx-target={@myself}
            phx-disable-with={gettext("Adding…")}
            class="flex w-full items-baseline justify-between gap-3 rounded-lg px-3 py-2 text-left text-sm hover:bg-zinc-100 focus:bg-zinc-100 focus:outline-none dark:hover:bg-zinc-800 dark:focus:bg-zinc-800"
          >
            <span>{cand.name}</span>
            <span class="truncate text-xs opacity-60">
              {[cand.admin1, Basa.Geo.Countries.name(cand.country_code, @locale)]
              |> Enum.reject(&(&1 in [nil, ""]))
              |> Enum.join(", ")}
            </span>
          </button>
        </div>

        <p :if={@results == [] and @candidates == []} class="px-3 py-3 text-sm opacity-70">
          {if @mode == :service,
            do: gettext("No offers in this city yet. We've noted it."),
            else: gettext("No city found. Check the spelling.")}
        </p>
      </div>

      <p :if={@note} class="mt-1 text-xs text-amber-600">{@note}</p>
      <p :for={e <- @errors} class="mt-1 text-xs text-rose-600">{e}</p>
    </div>
    """
  end
end
