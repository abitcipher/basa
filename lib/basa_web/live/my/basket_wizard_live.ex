defmodule BasaWeb.My.BasketWizardLive do
  use BasaWeb, :live_view

  alias Basa.Catalog
  alias BasaWeb.KeepState

  @steps 3

  @impl true
  def mount(params, _session, socket) do
    actor = socket.assigns.current_user

    {basket, draft} =
      case params do
        %{"id" => id} ->
          b = Catalog.get_basket!(id, actor: actor, load: [:items, :attendants])

          {b,
           %{
             "title" => b.title,
             "description" => b.description,
             "service_type" => to_string(b.service_type),
             "item_ids" => MapSet.new(b.items, & &1.id),
             "attendant_ids" => MapSet.new(b.attendants, & &1.id)
           }}

        _ ->
          {nil,
           %{
             "title" => "",
             "description" => "",
             "service_type" => "equipment_rental",
             "item_ids" => MapSet.new(),
             "attendant_ids" => MapSet.new()
           }}
      end

    {:ok,
     socket
     |> assign(page_title: gettext("Basket"), basket: basket, draft: draft, step: 0, error: nil)
     |> KeepState.start("basket-wizard:" <> ((basket && basket.id) || "new"), draft)
     |> assign(
       items: Catalog.list_my_items!(actor: actor),
       attendants: Catalog.list_my_attendants!(actor: actor)
     )}
  end

  @impl true
  def handle_event("details", %{"basket" => params}, socket) do
    draft =
      Map.merge(socket.assigns.draft, Map.take(params, ["title", "description", "service_type"]))

    if String.trim(draft["title"]) == "",
      do: {:noreply, assign(socket, draft: draft, error: gettext("Give the basket a name."))},
      else: {:noreply, assign(socket, draft: draft, error: nil, step: 1)}
  end

  def handle_event("details_change", %{"basket" => params}, socket) do
    {:noreply, update(socket, :draft, &Map.merge(&1, Map.take(params, ["title", "description"])))}
  end

  def handle_event("pick_service", %{"service" => value}, socket) do
    {:noreply, update(socket, :draft, &Map.put(&1, "service_type", value))}
  end

  def handle_event("toggle", %{"kind" => kind, "id" => id}, socket) do
    key = "#{kind}_ids"

    draft =
      Map.update!(socket.assigns.draft, key, fn set ->
        if MapSet.member?(set, id), do: MapSet.delete(set, id), else: MapSet.put(set, id)
      end)

    {:noreply, assign(socket, draft: draft)}
  end

  def handle_event("add_attendant", %{"attendant" => params}, socket) do
    case Catalog.create_attendant(params, actor: socket.assigns.current_user) do
      {:ok, a} ->
        draft = Map.update!(socket.assigns.draft, "attendant_ids", &MapSet.put(&1, a.id))
        {:noreply, assign(socket, draft: draft, attendants: socket.assigns.attendants ++ [a])}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Add a name for the person."))}
    end
  end

  def handle_event("keep:restore", %{"token" => token}, socket) do
    case KeepState.restore(socket, token) do
      {:ok, {step, draft}} -> {:reply, %{ok: true}, assign(socket, step: step, draft: draft)}
      :error -> {:reply, %{ok: false}, socket}
    end
  end

  def handle_event("goto", %{"step" => step}, socket) do
    step = String.to_integer(step)

    cond do
      step == 2 and
          MapSet.size(socket.assigns.draft["item_ids"]) +
            MapSet.size(socket.assigns.draft["attendant_ids"]) == 0 ->
        {:noreply, assign(socket, error: gettext("Pick at least one item or person."))}

      step in 0..(@steps - 1) ->
        {:noreply, assign(socket, step: step, error: nil)}
    end
  end

  def handle_event("save", _params, socket) do
    %{draft: d, basket: basket, current_user: actor} = socket.assigns

    attrs = %{
      title: d["title"],
      description: d["description"],
      service_type: String.to_existing_atom(d["service_type"]),
      item_ids: MapSet.to_list(d["item_ids"]),
      attendant_ids: MapSet.to_list(d["attendant_ids"])
    }

    result =
      if basket,
        do: Catalog.update_basket(basket, attrs, actor: actor),
        else: Catalog.create_basket(attrs, actor: actor)

    case result do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(
           :info,
           gettext("Basket saved. Next: place it in a room and publish an offer.")
         )
         |> KeepState.forget()
         |> push_navigate(to: ~p"/my")}

      {:error, error} ->
        {:noreply, assign(socket, error: Enum.join(BasaWeb.ErrorText.messages(error), "; "))}
    end
  end

  defp selected(draft, kind, list),
    do: Enum.filter(list, &MapSet.member?(draft["#{kind}_ids"], &1.id))

  defp total_value(items) do
    items
    |> Enum.map(&(&1.estimated_value || Decimal.new(0)))
    |> Enum.reduce(Decimal.new(0), &Decimal.add/2)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} unread={@unread_count} active={:my}>
      <KeepState.kept keep={@keep} data={{@step, @draft}} />
      <.page_title title={if @basket, do: gettext("Edit basket"), else: gettext("New basket")} />
      <.wizard_steps
        steps={[gettext("Name"), gettext("Contents"), gettext("Review")]}
        current={@step}
      />
      <.alert :if={@error} kind={:danger} rounded="large" class="mb-4">{@error}</.alert>

      <%= case @step do %>
        <% 0 -> %>
          <form id="basket-details" phx-submit="details" phx-change="details_change" class="space-y-4">
            <.text_field
              name="basket[title]"
              value={@draft["title"]}
              label={gettext("Name")}
              placeholder={gettext("Vocal recording kit")}
              size="medium"
            />
            <div>
              <p class="mb-2 text-sm font-medium">{gettext("What is it mostly?")}</p>
              <.choice_buttons
                options={service_types()}
                selected={@draft["service_type"]}
                event="pick_service"
                key="service"
              />
            </div>
            <.textarea_field
              name="basket[description]"
              value={@draft["description"]}
              label={gettext("Description (optional)")}
              rows="3"
            />
            <div class="flex justify-end">
              <.button type="submit" color="primary" variant="default">{gettext("Next")}</.button>
            </div>
          </form>
        <% 1 -> %>
          <section>
            <.page_title title={gettext("Items")} level={2}>
              <:action>
                <.button_link
                  navigate={~p"/my/items/new"}
                  size="extra_small"
                  variant="transparent"
                  icon="hero-plus"
                >{gettext("New item")}</.button_link>
              </:action>
            </.page_title>
            <div class="grid grid-cols-2 gap-2 sm:grid-cols-3">
              <.select_card
                :for={item <- @items}
                selected={MapSet.member?(@draft["item_ids"], item.id)}
                phx-click="toggle"
                phx-value-kind="item"
                phx-value-id={item.id}
              >
                <div class="aspect-[4/3]"><.photo key={List.first(item.photos)} /></div>
                <div class="p-2 text-sm">
                  <p class="line-clamp-1 font-medium">{item.title}</p>
                  <p class="text-xs opacity-70">
                    {Basa.Money.format(item.estimated_value, item.currency)}
                  </p>
                </div>
              </.select_card>
            </div>
            <.empty_state :if={@items == []} title={gettext("No items yet")} icon="hero-camera">
              <:action>
                <.button_link navigate={~p"/my/items/new"} size="small" variant="bordered">{gettext(
                  "Add an item"
                )}</.button_link>
              </:action>
            </.empty_state>
          </section>

          <section class="mt-6">
            <.page_title title={gettext("People (optional)")} level={2} />
            <div class="mb-3 flex flex-wrap gap-2">
              <.button
                :for={a <- @attendants}
                type="button"
                phx-click="toggle"
                phx-value-kind="attendant"
                phx-value-id={a.id}
                size="small"
                rounded="full"
                variant={
                  if MapSet.member?(@draft["attendant_ids"], a.id), do: "default", else: "bordered"
                }
                color={
                  if MapSet.member?(@draft["attendant_ids"], a.id), do: "primary", else: "natural"
                }
              >
                {a.name} · {BasaWeb.LotLive.role_label(a.role)}
              </.button>
            </div>
            <form id="add-attendant" phx-submit="add_attendant" class="flex flex-wrap items-end gap-2">
              <div class="min-w-48 flex-1">
                <.text_field
                  name="attendant[name]"
                  placeholder={gettext("Name, e.g. sound engineer Ivan")}
                  size="small"
                />
              </div>
              <.native_select id="attendant-role" name="attendant[role]" size="small" class="w-auto">
                <:option value="sound_engineer">{gettext("Sound engineer")}</:option>
                <:option value="assistant">{gettext("Assistant")}</:option>
                <:option value="guide">{gettext("Guide")}</:option>
                <:option value="key_holder">{gettext("Key holder")}</:option>
                <:option value="specialist">{gettext("Specialist")}</:option>
              </.native_select>
              <.button type="submit" size="small" variant="bordered">{gettext("Add")}</.button>
            </form>
          </section>

          <div class="mt-6 flex justify-between">
            <.button variant="transparent" phx-click="goto" phx-value-step="0">{gettext("Back")}</.button>
            <.button color="primary" variant="default" phx-click="goto" phx-value-step="2">{gettext(
              "Next"
            )}</.button>
          </div>
        <% 2 -> %>
          <.card padding="medium" rounded="large">
            <h2 class="text-lg font-semibold">{@draft["title"]}</h2>
            <p :if={@draft["description"] != ""} class="opacity-80">{@draft["description"]}</p>
            <ul class="mt-2 list-disc pl-5">
              <li :for={i <- selected(@draft, "item", @items)}>{i.title}</li>
              <li :for={a <- selected(@draft, "attendant", @attendants)}>
                {a.name} ({BasaWeb.LotLive.role_label(a.role)})
              </li>
            </ul>
            <p class="mt-2 text-sm opacity-70">
              {gettext("Total market value")}: {Decimal.to_string(
                total_value(selected(@draft, "item", @items))
              )}
            </p>
          </.card>
          <div class="mt-6 flex justify-between">
            <.button variant="transparent" phx-click="goto" phx-value-step="1">{gettext("Back")}</.button>
            <.button
              color="primary"
              variant="default"
              phx-click="save"
              phx-disable-with={gettext("Saving…")}
            >{gettext("Save basket")}</.button>
          </div>
      <% end %>
    </Layouts.app>
    """
  end

  defp service_types do
    [
      {"equipment_rental", gettext("Equipment")},
      {"venue_rental", gettext("Venue")},
      {"person_time", gettext("A person's time")},
      {"mixed", gettext("Mixed")}
    ]
  end
end
