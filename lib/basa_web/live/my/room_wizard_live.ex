defmodule BasaWeb.My.RoomWizardLive do
  use BasaWeb, :live_view

  alias Basa.{Catalog, JsonSchema}
  alias BasaWeb.{KeepState, PhotoUploads}

  @max_photos 8

  @impl true
  def mount(params, _session, socket) do
    actor = socket.assigns.current_user

    categories =
      Catalog.list_categories!(authorize?: false)
      |> Enum.filter(&(&1.kind == :venue))
      |> Enum.sort_by(& &1.position)

    {room, draft} =
      case params do
        %{"id" => id} ->
          r = Catalog.get_room!(id, actor: actor)

          {r,
           r
           |> Map.take([
             :title,
             :description,
             :city,
             :city_id,
             :address,
             :lat,
             :lng,
             :placement,
             :mobile,
             :service_radius_km,
             :capacity,
             :attrs,
             :photos,
             :category_id,
             :street_view,
             :entrance_photos
           ])
           |> Map.new(fn {k, v} -> {to_string(k), v} end)}

        _ ->
          last = Catalog.list_my_rooms!(actor: actor) |> List.first()
          city = (last && Basa.Geo.get(last.city_id)) || List.first(Basa.Geo.popular(1))

          {nil,
           %{
             "title" => "",
             "description" => "",
             "city" => (city && city.name) || "",
             "city_id" => city && city.id,
             "address" => "",
             "lat" => (city && city.lat) || 50.4501,
             "lng" => (city && city.lng) || 30.5234,
             "placement" => :above_ground,
             "mobile" => false,
             "service_radius_km" => 20,
             "capacity" => nil,
             "attrs" => %{},
             "photos" => [],
             "street_view" => nil,
             "entrance_photos" => [],
             "category_id" => categories |> List.first() |> then(&(&1 && &1.id))
           }}
      end

    {:ok,
     socket
     |> assign(
       page_title: gettext("Room"),
       room: room,
       draft: draft,
       step: 0,
       errors: [],
       max_photos: @max_photos,
       photo_notice: nil,
       categories: categories,
       street_views: nil,
       street_error: nil,
       street_enabled?: Basa.StreetView.enabled?()
     )
     |> KeepState.start("room-wizard:" <> ((room && room.id) || "new"), draft)
     |> allow_upload(:photos,
       accept: ~w(.jpg .jpeg .png .webp),
       max_entries: @max_photos,
       max_file_size: 12_000_000,
       auto_upload: true,
       progress: &handle_progress/3
     )
     |> allow_upload(:entrance,
       accept: ~w(.jpg .jpeg .png .webp),
       max_entries: Basa.Catalog.Room.max_entrance_photos(),
       max_file_size: 12_000_000,
       auto_upload: true,
       progress: &handle_progress/3
     )}
  end

  defp handle_progress(:entrance, entry, socket) do
    if entry.done? do
      prefix = "entrance/#{socket.assigns.current_user.id}"
      count = length(socket.assigns.draft["entrance_photos"] || [])
      max = Basa.Catalog.Room.max_entrance_photos()

      case PhotoUploads.store(socket, entry, prefix, count, max) do
        {:stored, key} ->
          {:noreply,
           update(
             socket,
             :draft,
             &Map.update(&1, "entrance_photos", [key], fn p -> p ++ [key] end)
           )}

        :full ->
          {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  defp handle_progress(:photos, entry, socket) do
    if entry.done? do
      prefix = "rooms/#{socket.assigns.current_user.id}"
      count = length(socket.assigns.draft["photos"])

      case PhotoUploads.store(socket, entry, prefix, count, @max_photos) do
        {:stored, key} ->
          {:noreply, update(socket, :draft, &Map.update!(&1, "photos", fn p -> p ++ [key] end))}

        :full ->
          {:noreply, assign(socket, photo_notice: PhotoUploads.notice(@max_photos))}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("change", %{"room" => params}, socket) do
    {:noreply, assign(socket, draft: merge(socket.assigns.draft, params, socket))}
  end

  def handle_event("change", _params, socket), do: {:noreply, socket}

  def handle_event("placement", %{"placement" => value}, socket) do
    {:noreply, update(socket, :draft, &Map.put(&1, "placement", String.to_existing_atom(value)))}
  end

  def handle_event("pin", %{"lat" => lat, "lng" => lng}, socket) do
    {:noreply, update(socket, :draft, &Map.merge(&1, %{"lat" => lat, "lng" => lng}))}
  end

  def handle_event("street_find", _params, socket) do
    %{"lat" => lat, "lng" => lng} = socket.assigns.draft

    {:noreply,
     socket
     |> assign(street_views: :loading, street_error: nil)
     |> start_async(:street_views, fn -> Basa.StreetView.nearby(lat, lng) end)}
  end

  def handle_event("street_pick", %{"id" => id}, socket) do
    with views when is_list(views) <- socket.assigns.street_views,
         %{} = view <- Enum.find(views, &(&1.id == id)),
         {:ok, kept} <- Basa.StreetView.keep(view, socket.assigns.current_user.id) do
      {:noreply,
       socket
       |> update(:draft, &Map.put(&1, "street_view", kept))
       |> assign(street_views: nil, street_error: nil)}
    else
      _ ->
        {:noreply, assign(socket, street_error: gettext("That didn't work. Please try again."))}
    end
  end

  def handle_event("street_none", _params, socket),
    do: {:noreply, assign(socket, street_views: nil, street_error: nil)}

  def handle_event("street_remove", _params, socket),
    do: {:noreply, update(socket, :draft, &Map.put(&1, "street_view", nil))}

  def handle_event("keep:restore", %{"token" => token}, socket) do
    case KeepState.restore(socket, token) do
      {:ok, {step, draft}} ->
        {:reply, %{ok: true},
         socket
         |> assign(step: step, draft: draft)
         |> push_event("map:center", %{lat: draft["lat"], lng: draft["lng"]})
         |> push_event("map:refresh", %{})}

      :error ->
        {:reply, %{ok: false}, socket}
    end
  end

  def handle_event("goto", %{"step" => step}, socket) do
    step = String.to_integer(step)
    d = socket.assigns.draft

    cond do
      step > 0 and String.trim(d["title"] || "") == "" ->
        {:noreply, assign(socket, errors: [gettext("Give the room a name.")])}

      step > 1 and d["city_id"] in [nil, ""] ->
        {:noreply, assign(socket, errors: [gettext("Pick a city.")])}

      step == 1 ->
        {:noreply, socket |> assign(step: step, errors: []) |> push_event("map:refresh", %{})}

      true ->
        {:noreply, assign(socket, step: step, errors: [])}
    end
  end

  def handle_event("move_photo", %{"key" => key, "dir" => dir}, socket) do
    {:noreply,
     update(
       socket,
       :draft,
       &Map.update!(&1, "photos", fn p -> BasaWeb.PhotoOrder.move(p, key, dir) end)
     )}
  end

  def handle_event("reorder_photos", %{"keys" => keys}, socket) do
    {:noreply,
     update(
       socket,
       :draft,
       &Map.update!(&1, "photos", fn p -> BasaWeb.PhotoOrder.reorder(p, keys) end)
     )}
  end

  def handle_event("remove_photo", %{"key" => key}, socket) do
    {:noreply,
     socket
     |> update(:draft, &Map.update!(&1, "photos", fn p -> List.delete(p, key) end))
     |> assign(photo_notice: nil)}
  end

  def handle_event("cancel_upload", %{"ref" => ref}, socket),
    do: {:noreply, cancel_upload(socket, :photos, ref)}

  def handle_event("entrance_remove", %{"key" => key}, socket),
    do:
      {:noreply,
       update(
         socket,
         :draft,
         &Map.update(&1, "entrance_photos", [], fn p -> List.delete(p, key) end)
       )}

  def handle_event("entrance_cancel", %{"ref" => ref}, socket),
    do: {:noreply, cancel_upload(socket, :entrance, ref)}

  def handle_event("noop", _params, socket), do: {:noreply, socket}

  def handle_event("save", _params, socket) do
    %{draft: d, room: room, current_user: actor} = socket.assigns
    attrs = d |> Map.new(fn {k, v} -> {String.to_existing_atom(k), v} end)
    attrs = if attrs.mobile, do: attrs, else: Map.put(attrs, :service_radius_km, nil)

    result =
      if room,
        do: Catalog.update_room(room, attrs, actor: actor),
        else: Catalog.create_room(attrs, actor: actor)

    case result do
      {:ok, _room} ->
        {:noreply,
         socket
         |> KeepState.forget()
         |> put_flash(:info, gettext("Room saved."))
         |> push_navigate(to: ~p"/my")}

      {:error, error} ->
        {:noreply, assign(socket, errors: BasaWeb.ErrorText.messages(error))}
    end
  end

  @impl true
  def handle_async(:street_views, {:ok, {:ok, views}}, socket),
    do: {:noreply, assign(socket, street_views: views)}

  def handle_async(:street_views, _result, socket) do
    {:noreply,
     assign(socket,
       street_views: nil,
       street_error: gettext("Street views can't be looked up right now.")
     )}
  end

  @impl true
  def handle_info({BasaWeb.CityPicker, "room-city", nil}, socket),
    do: {:noreply, update(socket, :draft, &Map.merge(&1, %{"city_id" => nil, "city" => ""}))}

  def handle_info({BasaWeb.CityPicker, "room-city", city}, socket) do
    {:noreply,
     socket
     |> update(
       :draft,
       &Map.merge(&1, %{
         "city_id" => city.id,
         "city" => city.name,
         "lat" => city.lat,
         "lng" => city.lng
       })
     )
     |> push_event("map:center", %{lat: city.lat, lng: city.lng})}
  end

  defp merge(draft, params, socket) do
    category = category(params["category_id"] || draft["category_id"], socket.assigns)
    schema = category && category.attr_schema

    params
    |> Map.take([
      "title",
      "description",
      "address",
      "category_id",
      "capacity",
      "service_radius_km"
    ])
    |> Map.merge(
      if Map.has_key?(params, "mobile"), do: %{"mobile" => params["mobile"] == "true"}, else: %{}
    )
    |> Map.merge(
      if params["attrs"],
        do: %{"attrs" => JsonSchema.cast_params(schema, params["attrs"])},
        else: %{}
    )
    |> Map.update("capacity", draft["capacity"], &int/1)
    |> Map.update("service_radius_km", draft["service_radius_km"], &int/1)
    |> then(&Map.merge(draft, &1))
  end

  defp category(id, %{categories: categories}), do: Enum.find(categories, &(&1.id == id))

  defp int(v) when v in [nil, ""], do: nil
  defp int(v) when is_integer(v), do: v
  defp int(v), do: String.to_integer(v)

  attr :photos, :list, required: true
  attr :upload, :any, required: true

  defp entrance_photos(assigns) do
    assigns = assign(assigns, max: Basa.Catalog.Room.max_entrance_photos())

    ~H"""
    <div id="entrance-photos" class="space-y-1">
      <p class="text-sm">{gettext("Your photos of the entrance or street")}</p>
      <div class="flex flex-wrap gap-2">
        <div
          :for={key <- @photos}
          id={"entrance-#{Path.basename(key, Path.extname(key))}"}
          class="relative size-20 overflow-hidden rounded-lg"
        >
          <.photo key={key} />
          <button
            type="button"
            phx-click="entrance_remove"
            phx-value-key={key}
            class="absolute top-1 right-1 cursor-pointer rounded-full bg-white/90 p-0.5 text-zinc-800"
            aria-label={gettext("Remove photo")}
          >
            <.icon name="hero-trash" class="size-4" />
          </button>
        </div>
        <div
          :for={entry <- @upload.entries}
          class="flex size-20 flex-col items-center justify-center gap-1 rounded-lg bg-zinc-100 p-1 text-center text-xs dark:bg-zinc-800"
        >
          <.progress value={entry.progress} size="small" color="primary" class="w-4/5" />
          <button
            type="button"
            phx-click="entrance_cancel"
            phx-value-ref={entry.ref}
            class="cursor-pointer underline"
          >
            {gettext("cancel")}
          </button>
        </div>
        <label
          :if={length(@photos) + length(@upload.entries) < @max}
          class="flex size-20 cursor-pointer flex-col items-center justify-center rounded-lg border-2 border-dashed border-zinc-300 text-xs opacity-80 dark:border-zinc-700"
        >
          <.icon name="hero-camera" class="size-6" />
          {gettext("Add")}
          <.live_file_input upload={@upload} class="hidden" />
        </label>
      </div>
    </div>
    """
  end

  attr :view, :map, default: nil
  attr :views, :any, default: nil
  attr :error, :string, default: nil
  attr :enabled, :boolean, default: false

  defp street_view_picker(assigns) do
    ~H"""
    <div id="street-view" class="space-y-2">
      <div class="flex items-center gap-2">
        <p class="text-sm">{gettext("Street view")}</p>
        <.info_tip id="street-view-info">
          {gettext(
            "A street-level photo near the address helps renters find the entrance. It is shown beside the map, never as a photo of the room. Pick one only if it shows your building."
          )}
        </.info_tip>
      </div>

      <div :if={@view} id="street-view-picked" class="flex flex-wrap items-end gap-3">
        <img src={Basa.Storage.url(@view["key"])} alt="" class="h-28 rounded-lg object-cover" />
        <div class="space-y-1">
          <.street_view_credit view={@view} />
          <.button
            id="street-view-remove"
            type="button"
            size="small"
            variant="bordered"
            color="natural"
            phx-click="street_remove"
          >
            {gettext("Remove")}
          </.button>
        </div>
      </div>

      <div :if={!@view and @enabled}>
        <.button
          :if={@views in [nil, []]}
          id="street-view-find"
          type="button"
          size="small"
          variant="bordered"
          color="natural"
          phx-click="street_find"
        >
          {gettext("Find street views near the pin")}
        </.button>
        <p :if={@views == []} id="street-view-none-found" class="mt-2 text-sm opacity-70">
          {gettext("No street views near the pin yet.")}
        </p>
        <p :if={@views == :loading} class="text-sm opacity-70">{gettext("Looking…")}</p>
        <div :if={is_list(@views) and @views != []} id="street-view-choices" class="space-y-2">
          <div class="grid grid-cols-2 gap-2 sm:grid-cols-3">
            <button
              :for={v <- @views}
              id={"street-view-#{v.id}"}
              type="button"
              phx-click="street_pick"
              phx-value-id={v.id}
              class="overflow-hidden rounded-lg border border-zinc-200 text-left text-xs hover:ring-2 hover:ring-[var(--brand-cyan,#00ccff)] dark:border-zinc-800"
            >
              <img src={v.preview} alt="" class="aspect-[4/3] w-full object-cover" />
              <span class="block px-2 py-1 opacity-80">
                {gettext("%{m} m away", m: v.meters)}<span :if={v.captured_at}> · {v.captured_at.year}</span>
              </span>
            </button>
          </div>
          <.button
            id="street-view-skip"
            type="button"
            size="small"
            variant="transparent"
            color="natural"
            phx-click="street_none"
          >
            {gettext("None of these show my building")}
          </.button>
        </div>
      </div>

      <p :if={@error} class="text-sm text-rose-600">{@error}</p>
    </div>
    """
  end

  @impl true
  def render(assigns) do
    assigns =
      assigns
      |> assign(:category, category(assigns.draft["category_id"], assigns))
      |> assign(:city, Basa.Geo.get(assigns.draft["city_id"]))

    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} unread={@unread_count} active={:my}>
      <KeepState.kept keep={@keep} data={{@step, @draft}} />
      <.page_title title={if @room, do: gettext("Edit room"), else: gettext("New room")} />
      <.wizard_steps
        steps={[gettext("Basics"), gettext("Location"), gettext("Details")]}
        current={@step}
      />
      <.alert :if={@errors != []} kind={:danger} rounded="large" class="mb-4">
        <ul>
          <li :for={e <- @errors}>{e}</li>
        </ul>
      </.alert>

      <form id="room-form" phx-change="change" phx-submit="save" class="space-y-4">
        <div class={["space-y-4", @step != 0 && "hidden"]}>
          <.text_field
            name="room[title]"
            value={@draft["title"]}
            label={gettext("Name")}
            placeholder={gettext("Studio A, Moldavanka")}
            size="medium"
          />
          <.native_select
            id="room-category-id"
            name="room[category_id]"
            label={gettext("Type of place")}
            size="medium"
          >
            <:option :for={c <- @categories} value={c.id} selected={c.id == @draft["category_id"]}>
              {Basa.Catalog.Category.display_name(c, Gettext.get_locale(BasaWeb.Gettext))}
            </:option>
          </.native_select>
          <div>
            <p class="mb-2 text-sm font-medium">{gettext("Where is it?")}</p>
            <.choice_buttons
              options={placements()}
              selected={@draft["placement"]}
              event="placement"
              key="placement"
              cols="grid-cols-3"
            />
          </div>
        </div>

        <div class={["space-y-3", @step != 1 && "hidden"]}>
          <div class="grid gap-3 sm:grid-cols-2">
            <.live_component
              module={BasaWeb.CityPicker}
              id="room-city"
              name="room[city_id]"
              city={@city}
              mode={:any}
              label={gettext("City")}
            />
            <.text_field
              name="room[address]"
              value={@draft["address"]}
              label={gettext("Address")}
              size="medium"
            />
          </div>
          <div class="relative">
            <div
              id="room-map"
              phx-hook="MapPicker"
              phx-update="ignore"
              data-lat={@draft["lat"]}
              data-lng={@draft["lng"]}
              class="relative z-0 h-64 overflow-hidden rounded-xl bg-zinc-100 dark:bg-zinc-800"
            >
            </div>
            <.info_tip
              id="room-map-info"
              align="end"
              class="absolute top-2 right-2 z-10 rounded-full bg-white/90 p-0.5 text-zinc-800"
            >
              {gettext("Drag the pin to the entrance.")}
            </.info_tip>
          </div>

          <div
            id="how-to-find"
            class="space-y-3 rounded-xl border border-zinc-200 p-3 dark:border-zinc-800"
          >
            <div class="flex items-center gap-2">
              <p class="text-sm font-semibold">{gettext("How to find it (optional)")}</p>
              <.info_tip id="how-to-find-info">
                {gettext(
                  "Photos of the entrance or the street help renters find the place. They are shown beside the map, not among the room's photos."
                )}
              </.info_tip>
            </div>
            <.entrance_photos photos={@draft["entrance_photos"] || []} upload={@uploads.entrance} />
            <.street_view_picker
              :if={@street_enabled? or @draft["street_view"]}
              view={@draft["street_view"]}
              views={@street_views}
              error={@street_error}
              enabled={@street_enabled?}
            />
          </div>

          <.toggle_field
            id="room-mobile"
            name="room[mobile]"
            checked={@draft["mobile"]}
            label={gettext("Mobile setup")}
            description={gettext("It can come to the renter")}
            size="small"
          />
          <.range_field
            :if={@draft["mobile"]}
            name="room[service_radius_km]"
            value={@draft["service_radius_km"]}
            min="1"
            max="200"
            label={gettext("Travels up to %{km} km", km: @draft["service_radius_km"])}
            size="small"
          />
        </div>

        <div class={["space-y-4", @step != 2 && "hidden"]}>
          <.number_field
            name="room[capacity]"
            value={@draft["capacity"]}
            min="1"
            label={gettext("Capacity (people)")}
            size="medium"
          />
          <.schema_fields
            :if={@category}
            schema={@category.attr_schema}
            values={@draft["attrs"] || %{}}
            prefix="room[attrs]"
          />
          <.textarea_field
            name="room[description]"
            value={@draft["description"]}
            label={gettext("Description")}
            rows="3"
          />
        </div>
      </form>

      <div :if={@step == 2} class="mt-4">
        <p class="mb-2 font-medium">{gettext("Photos")}</p>
        <.photo_uploader
          id="room-photos"
          upload={@uploads.photos}
          photos={@draft["photos"]}
          max={@max_photos}
          change="change"
          notice={@photo_notice}
        />
      </div>

      <div class="mt-6 flex justify-between">
        <.button :if={@step > 0} variant="transparent" phx-click="goto" phx-value-step={@step - 1}>{gettext(
          "Back"
        )}</.button>
        <span :if={@step == 0}></span>
        <.button
          :if={@step < 2}
          color="primary"
          variant="default"
          phx-click="goto"
          phx-value-step={@step + 1}
        >{gettext("Next")}</.button>
        <.button
          :if={@step == 2}
          type="submit"
          form="room-form"
          color="primary"
          variant="default"
          phx-disable-with={gettext("Saving…")}
        >
          {gettext("Save room")}
        </.button>
      </div>
    </Layouts.app>
    """
  end

  defp placements do
    [
      {:above_ground, gettext("Above ground"), "∧ [•]"},
      {:underground, gettext("Underground"), "∨ [+]"},
      {:open_area, gettext("Open area"), "⊻ [⊕]"}
    ]
  end
end
