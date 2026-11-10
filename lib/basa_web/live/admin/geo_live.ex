defmodule BasaWeb.Admin.GeoLive do
  use BasaWeb, :live_view

  require Ash.Query
  alias Basa.Geo

  @impl true
  def mount(_params, _session, socket) do
    if socket.assigns.current_user.role == :admin do
      {:ok, socket |> assign(page_title: gettext("Cities")) |> load()}
    else
      {:ok, socket |> put_flash(:error, gettext("Admins only.")) |> push_navigate(to: ~p"/")}
    end
  end

  defp load(socket) do
    actor = socket.assigns.current_user

    wanted =
      Geo.Demand
      |> Ash.Query.filter(status == :open)
      |> Ash.Query.sort(count: :desc, last_searched_at: :desc)
      |> Ash.Query.limit(100)
      |> Ash.read!(actor: actor)

    counts =
      Basa.Repo.query!("SELECT origin, count(*) FROM geo_cities GROUP BY origin").rows
      |> Map.new(fn [origin, n] -> {origin, n} end)

    assign(socket, wanted: wanted, counts: counts, top: Geo.popular(10))
  end

  @impl true
  def handle_event("add", %{"id" => id}, socket) do
    demand = Enum.find(socket.assigns.wanted, &(&1.id == id))

    case Geo.add_wanted(demand, socket.assigns.current_user) do
      {:ok, city} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("%{city} added.", city: city.name))
         |> load()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Couldn't add this place."))}
    end
  end

  def handle_event("ignore", %{"id" => id}, socket) do
    demand = Enum.find(socket.assigns.wanted, &(&1.id == id))
    Geo.resolve_demand!(demand, :ignored, actor: socket.assigns.current_user)
    {:noreply, load(socket)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} unread={@unread_count} wide>
      <.page_title title={gettext("Cities")} info_id="cities-info">
        <:info>
          {gettext(
            "Lessees only see cities BASA has. Searches for other places are counted here; add the ones people want."
          )}
        </:info>
      </.page_title>

      <div class="mb-6 grid grid-cols-3 gap-3">
        <.card
          :for={
            {origin, label} <- [
              {"seed", gettext("Starting list")},
              {"lessor", gettext("Added with rooms")},
              {"admin", gettext("Added by admins")}
            ]
          }
          padding="small"
          rounded="large"
        >
          <p class="text-2xl font-bold">{@counts[origin] || 0}</p>
          <p class="text-xs opacity-70">{label}</p>
        </.card>
      </div>

      <h2 class="mb-2 font-semibold">{gettext("Wanted places")}</h2>
      <.empty_state :if={@wanted == []} title={gettext("No searches for missing cities yet.")} />
      <div class="space-y-2">
        <.card :for={d <- @wanted} padding="small" rounded="large">
          <div class="flex flex-wrap items-center justify-between gap-3">
            <div class="min-w-0">
              <p class="font-medium">
                {d.label}
                <span class="ml-1 text-xs opacity-60">
                  {ngettext("1 search", "%{count} searches", d.count)}
                </span>
              </p>
              <p class="text-xs opacity-60">
                {gettext("Last query: %{q}", q: d.query)} · {if d.candidate,
                  do: gettext("found on OpenStreetMap"),
                  else: gettext("not found on OpenStreetMap")}
              </p>
            </div>
            <div class="flex gap-2">
              <.button
                :if={d.candidate}
                size="small"
                color="primary"
                variant="default"
                phx-click="add"
                phx-value-id={d.id}
                phx-disable-with={gettext("Adding…")}
              >
                {gettext("Add")}
              </.button>
              <.button size="small" variant="bordered" phx-click="ignore" phx-value-id={d.id}>
                {gettext("Ignore")}
              </.button>
            </div>
          </div>
        </.card>
      </div>

      <h2 class="mb-2 mt-6 font-semibold">{gettext("Most picked")}</h2>
      <p class="text-sm opacity-80">
        {Enum.map_join(@top, " · ", &"#{&1.name} (#{&1.picks})")}
      </p>
    </Layouts.app>
    """
  end
end
