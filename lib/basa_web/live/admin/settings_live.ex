defmodule BasaWeb.Admin.SettingsLive do
  use BasaWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    if socket.assigns.current_user.role == :admin do
      {:ok,
       assign(socket,
         page_title: gettext("Settings"),
         settings: Basa.System.settings(),
         near_error: nil,
         near: near_form(Basa.System.settings())
       )
       |> moderation_status()}
    else
      {:ok, socket |> put_flash(:error, gettext("Admins only.")) |> push_navigate(to: ~p"/")}
    end
  end

  @impl true
  def handle_event("widgets", %{"enabled" => enabled}, socket) do
    {:ok, settings} =
      Basa.System.update_settings(socket.assigns.settings, %{widgets_enabled: enabled == "true"},
        actor: socket.assigns.current_user
      )

    {:noreply,
     socket
     |> assign(settings: settings, widgets?: settings.widgets_enabled)
     |> put_flash(:info, gettext("Saved. Pages opened from now on use this setting."))}
  end

  def handle_event("service", %{"service" => name, "on" => on}, socket) do
    service = Enum.find(Basa.Services.all(), &(to_string(&1) == name))
    off = socket.assigns.settings.services_off -- [service]
    off = if on == "true", do: off, else: [service | off]

    {:ok, settings} =
      Basa.System.update_settings(socket.assigns.settings, %{services_off: off},
        actor: socket.assigns.current_user
      )

    {:noreply,
     socket
     |> assign(settings: settings)
     |> put_flash(:info, gettext("Saved. Pages opened from now on use this setting."))}
  end

  def handle_event("moderation_level", %{"level" => level}, socket) do
    level = String.to_integer(level)

    if level in [1, 2] and level != socket.assigns.settings.moderation_level do
      {:ok, settings} =
        Basa.System.update_settings(socket.assigns.settings, %{moderation_level: level},
          actor: socket.assigns.current_user
        )

      {:noreply,
       socket
       |> assign(settings: settings)
       |> put_flash(:info, gettext("Saved. The checker prepares the new level."))
       |> moderation_status()}
    else
      {:noreply, socket}
    end
  end

  def handle_event("moderation_recheck", _params, socket) do
    count = Basa.Moderation.recheck_all()

    {:noreply,
     socket
     |> put_flash(:info, gettext("%{count} photos will be checked again.", count: count))
     |> moderation_status()}
  end

  def handle_event("sign_in", %{"method" => name, "on" => on}, socket) do
    method = Enum.find(Basa.Accounts.SignInMethods.all(), &(to_string(&1) == name))
    off = socket.assigns.settings.sign_in_off -- [method]
    off = if on == "true", do: off, else: [method | off]

    {:ok, settings} =
      Basa.System.update_settings(socket.assigns.settings, %{sign_in_off: off},
        actor: socket.assigns.current_user
      )

    {:noreply,
     socket
     |> assign(settings: settings)
     |> put_flash(:info, gettext("Saved. Pages opened from now on use this setting."))}
  end

  def handle_event("near_edit", %{"near" => p}, socket),
    do: {:noreply, assign(socket, near: near_form(near_attrs(p)))}

  def handle_event("near", %{"near" => p}, socket) do
    attrs = near_attrs(p)

    case Basa.System.update_settings(socket.assigns.settings, attrs,
           actor: socket.assigns.current_user
         ) do
      {:ok, settings} ->
        {:noreply,
         socket
         |> assign(settings: settings, near_error: nil, near: near_form(settings))
         |> put_flash(:info, gettext("Saved. Pages opened from now on use this setting."))}

      {:error, error} ->
        {:noreply,
         assign(socket,
           near_error: Enum.join(BasaWeb.ErrorText.messages(error), "; "),
           near: near_form(attrs)
         )}
    end
  end

  defp method_name(:google), do: "Google"
  defp method_name(:facebook), do: "Facebook"
  defp method_name(:instagram), do: "Instagram"
  defp method_name(:telegram), do: "Telegram"

  defp method_setup(:google), do: "GOOGLE_CLIENT_ID, GOOGLE_CLIENT_SECRET"
  defp method_setup(:facebook), do: "FACEBOOK_APP_ID, FACEBOOK_APP_SECRET"
  defp method_setup(:instagram), do: "INSTAGRAM_APP_ID, INSTAGRAM_APP_SECRET"
  defp method_setup(:telegram), do: "TELEGRAM_BOT_TOKEN, TELEGRAM_BOT_USERNAME"

  defp near_attrs(p),
    do: %{
      near_control: p["control"],
      near_steps_km: parse_km(p["steps"]),
      near_city: p["city"] == "true",
      near_region: p["region"] == "true",
      near_default: p["default"]
    }

  defp near_form(s),
    do: %{
      control: to_string(s.near_control),
      steps: s.near_steps_km,
      city: s.near_city,
      region: s.near_region,
      default: s.near_default,
      choices: Basa.System.near_values(s.near_steps_km, s.near_city, s.near_region)
    }

  defp parse_km(text) do
    (text || "")
    |> String.split([",", ";", " "], trim: true)
    |> Enum.flat_map(fn part ->
      case Integer.parse(part) do
        {km, ""} when km > 0 -> [km]
        _ -> []
      end
    end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp control_label(:slider), do: gettext("Slider with steps")
  defp control_label(:chips), do: gettext("Buttons")
  defp control_label(:select), do: gettext("List")

  defp step_label("city"), do: gettext("Whole city")
  defp step_label("region"), do: gettext("Whole region")
  defp step_label(km), do: gettext("%{km} km", km: km)

  @impl true
  def handle_info(:moderation_refresh, socket), do: {:noreply, moderation_status(socket)}

  defp moderation_status(socket) do
    status =
      case Basa.Moderation.status() do
        {:ok, status} -> status
        {:error, :not_installed} -> :not_installed
        {:error, _} -> :unavailable
      end

    if (is_map(status) and status["preparing"]) && connected?(socket),
      do: Process.send_after(self(), :moderation_refresh, 2_000)

    assign(socket,
      moderation: status,
      moderation_counts: Basa.Moderation.counts()
    )
  end

  defp megabytes(bytes), do: round(bytes / 1_000_000)

  defp level_name(1), do: gettext("1 · Light")
  defp level_name(2), do: gettext("2 · Standard")

  defp texts(:telegram),
    do:
      {gettext("Telegram"), gettext("The bot, messages to Telegram and sign-in with Telegram."),
       gettext(
         "Messages stay in BASA's inbox; people sign in with the email and password from their profile."
       )}

  defp texts(:email),
    do:
      {gettext("Email"), gettext("Account confirmation and password reset emails."),
       gettext("No emails are sent; a forgotten password can't be reset by email.")}

  defp texts(:mem),
    do:
      {gettext("MEM"), gettext("Confirming a contract in person in MEM (level 3)."),
       gettext("Not offered; contracts already confirmed keep their confirmation.")}

  defp texts(:qes),
    do:
      {gettext("Qualified signatures"),
       gettext("Signing with Дія.Підпис or an eIDAS provider, checked by the EU DSS (level 4)."),
       gettext(
         "Not offered; stored signatures still verify, and their EU check runs when switched on again."
       )}

  defp texts(:timestamp),
    do:
      {gettext("Timestamp authority"), gettext("The independent time of each sealed contract."),
       gettext(
         "Contracts are sealed without it; the timestamps are requested when switched on again."
       )}

  defp texts(:osm),
    do:
      {gettext("OpenStreetMap"), gettext("Finding cities BASA doesn't have yet."),
       gettext("Only cities BASA already has can be chosen; missed searches are still counted.")}

  defp texts(:images),
    do:
      {gettext("Pictures for listings"),
       gettext("Finding openly licensed pictures (Openverse) for items without photos."),
       gettext("Only pictures BASA already keeps are suggested; owners add their own photos.")}

  defp texts(:import),
    do:
      {gettext("Import from web pages"),
       gettext("Reading listings from web pages: name, price, photos and details."),
       gettext("Owners add their listings by hand.")}

  defp texts(:street_view),
    do:
      {gettext("Street view"),
       gettext("Finding street-level photos near a room (Mapillary) to help renters find it."),
       gettext("Owners can't pick new views; views already picked keep showing.")}

  defp texts(:moderation),
    do:
      {gettext("Photo checks"),
       gettext(
         "Checking every photo on this server with open image models (nudity, weapons, documents): clear cases are hidden, others go to an admin."
       ),
       gettext("Photos are not checked; they wait and are checked when it is switched on again.")}

  defp texts(:ai),
    do:
      {gettext("AI suggestions"), gettext("Suggestions from item photos (Claude)."),
       gettext("Items are described by hand.")}

  defp texts(:payments),
    do:
      {gettext("Payments"), gettext("Paying BASA's commission and premium services."),
       gettext("Payment buttons are hidden; payments already started still finish.")}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} unread={@unread_count}>
      <.page_title title={gettext("Settings")} help="admin" />

      <.card padding="medium" rounded="large" class="max-w-xl">
        <div class="flex items-start justify-between gap-4">
          <div>
            <h2 class="flex items-center gap-1.5 font-semibold">
              {gettext("Rich widgets")}
              <.info_tip id="widgets-info">
                {gettext(
                  "Interactive calendars and photo viewers. When off, pages show simpler versions and everything keeps working: search, booking, messages and payments."
                )}
              </.info_tip>
            </h2>
            <p :if={@settings.updated_by_email} class="mt-2 text-xs opacity-50">
              {gettext("Edited by %{who}", who: @settings.updated_by_email)}
            </p>
          </div>
          <.button
            id="widgets-toggle"
            size="small"
            variant={if @settings.widgets_enabled, do: "default", else: "bordered"}
            color={if @settings.widgets_enabled, do: "success", else: "natural"}
            phx-click="widgets"
            phx-value-enabled={to_string(!@settings.widgets_enabled)}
          >
            {if @settings.widgets_enabled, do: gettext("On"), else: gettext("Off")}
          </.button>
        </div>
      </.card>

      <.card id="sign-in-options" padding="medium" rounded="large" class="mt-6 max-w-xl">
        <h2 class="flex items-center gap-1.5 font-semibold">
          {gettext("Sign-in options")}
          <.info_tip id="sign-in-info">
            {gettext(
              "Buttons on the sign-in page besides email and password, which always stay. People who signed up with a switched-off option add a password on their profile."
            )}
          </.info_tip>
        </h2>
        <ul class="mt-2 divide-y divide-gray-200 dark:divide-gray-700">
          <li
            :for={method <- Basa.Accounts.SignInMethods.all()}
            id={"sign-in-#{method}"}
            class="flex items-center justify-between gap-4 py-3"
          >
            <h3 class="flex items-center gap-1.5 font-medium">
              {method_name(method)}
              <.info_tip :if={method == :instagram} id="sign-in-instagram-info">
                {gettext(
                  "Instagram signs in only professional (business or creator) accounts; Meta closed sign-in for personal ones."
                )}
              </.info_tip>
              <.info_tip :if={method == :telegram} id="sign-in-telegram-info">
                {gettext("Also needs the Telegram service on (Outside services below).")}
              </.info_tip>
            </h3>
            <%= cond do %>
              <% not Basa.Accounts.SignInMethods.configured?(method) -> %>
                <span class="flex items-center gap-1.5">
                  <.badge id={"sign-in-#{method}-unset"} size="extra_small" rounded="full">
                    {gettext("Not set up")}
                  </.badge>
                  <.info_tip id={"sign-in-#{method}-setup"} align="end">
                    {gettext("Set %{keys} on the server.", keys: method_setup(method))}
                  </.info_tip>
                </span>
              <% method in @settings.sign_in_off -> %>
                <.button
                  id={"sign-in-#{method}-toggle"}
                  size="small"
                  variant="bordered"
                  color="natural"
                  phx-click="sign_in"
                  phx-value-method={method}
                  phx-value-on="true"
                >
                  {gettext("Off")}
                </.button>
              <% true -> %>
                <.button
                  id={"sign-in-#{method}-toggle"}
                  size="small"
                  variant="default"
                  color="success"
                  phx-click="sign_in"
                  phx-value-method={method}
                  phx-value-on="false"
                >
                  {gettext("On")}
                </.button>
            <% end %>
          </li>
        </ul>
      </.card>

      <.card id="near-settings" padding="medium" rounded="large" class="mt-6 max-w-xl">
        <h2 class="flex items-center gap-1.5 font-semibold">
          {gettext("Near me search")}
          <.info_tip id="near-info">
            {gettext(
              "How far from their location lessees search. \"Whole city\" and \"whole region\" use the city they are in."
            )}
          </.info_tip>
        </h2>
        <form id="near-form" phx-change="near_edit" phx-submit="near" class="mt-3 space-y-4">
          <fieldset>
            <legend class="mb-1 text-sm font-medium">{gettext("Control")}</legend>
            <div class="flex flex-wrap gap-3">
              <label :for={c <- [:slider, :chips, :select]} class="flex items-center gap-1.5 text-sm">
                <input
                  type="radio"
                  name="near[control]"
                  value={c}
                  checked={@near.control == to_string(c)}
                  class="accent-[var(--ui-action)]"
                />
                {control_label(c)}
              </label>
            </div>
          </fieldset>
          <.text_field
            id="near-steps"
            name="near[steps]"
            value={Enum.join(@near.steps, ", ")}
            label={gettext("Distances, km")}
            placeholder="1, 10, 25, 75, 125"
            size="small"
          />
          <div class="flex flex-wrap gap-4 text-sm">
            <label class="flex items-center gap-1.5">
              <input type="hidden" name="near[city]" value="false" />
              <input
                type="checkbox"
                id="near-city"
                name="near[city]"
                value="true"
                checked={@near.city}
                class="accent-[var(--ui-action)]"
              />
              {gettext("Whole city")}
            </label>
            <label class="flex items-center gap-1.5">
              <input type="hidden" name="near[region]" value="false" />
              <input
                type="checkbox"
                id="near-region"
                name="near[region]"
                value="true"
                checked={@near.region}
                class="accent-[var(--ui-action)]"
              />
              {gettext("Whole region")}
            </label>
          </div>
          <.native_select
            id="near-default"
            name="near[default]"
            label={gettext("Chosen at first")}
            size="small"
          >
            <:option
              :for={step <- @near.choices}
              value={step}
              selected={step == @near.default}
            >
              {step_label(step)}
            </:option>
          </.native_select>
          <p :if={@near_error} id="near-error" class="text-sm text-rose-600">{@near_error}</p>
          <.button type="submit" size="small" color="primary" variant="default">
            {gettext("Save")}
          </.button>
        </form>
      </.card>

      <.card id="moderation" padding="medium" rounded="large" class="mt-6 max-w-xl">
        <h2 class="flex items-center gap-1.5 font-semibold">
          {gettext("Photo checks")}
          <.info_tip id="moderation-info">
            {gettext(
              "Open image models check every photo on this server; photos never leave it. A higher level downloads larger models once and checks more precisely, a little slower. The models in use keep checking until the new ones are ready."
            )}
          </.info_tip>
        </h2>

        <p
          :if={@moderation == :not_installed}
          id="moderation-missing"
          class="mt-2 text-sm text-amber-700 dark:text-amber-400"
        >
          {gettext("The checker is not installed on this server (docker compose build moderate).")}
        </p>

        <form
          :if={@moderation != :not_installed}
          id="moderation-level-form"
          phx-change="moderation_level"
          class="mt-3"
        >
          <label for="moderation-level" class="text-sm font-medium">{gettext("Level")}</label>
          <input
            id="moderation-level"
            type="range"
            name="level"
            min="1"
            max="2"
            step="1"
            value={@settings.moderation_level}
            class="mt-1 w-full accent-[var(--ui-action)]"
          />
          <div class="flex justify-between text-xs opacity-80">
            <span
              :for={{level, bytes} <- Basa.Moderation.level_sizes()}
              class={level == @settings.moderation_level && "font-semibold"}
            >
              {level_name(level)} · {gettext("%{mb} MB", mb: megabytes(bytes))}
            </span>
          </div>
        </form>

        <p :if={is_map(@moderation)} id="moderation-status" class="mt-3 text-sm">
          <%= cond do %>
            <% @moderation["preparing"] && @moderation["total"] > 0 -> %>
              {gettext("Preparing level %{level}: %{percent}%",
                level: @moderation["preparing"],
                percent: round(@moderation["done"] * 100 / @moderation["total"])
              )}
            <% @moderation["level"] -> %>
              {gettext("In use: level %{level}", level: @moderation["level"])}
            <% true -> %>
              {gettext("Starting…")}
          <% end %>
        </p>
        <p
          :if={is_map(@moderation) and @moderation["error"]}
          id="moderation-error"
          class="mt-1 text-sm text-rose-600"
        >
          {gettext("The new level could not be prepared: %{error}", error: @moderation["error"])}
        </p>
        <p :if={@moderation == :unavailable} class="mt-3 text-sm text-rose-600">
          {gettext("The checker is not answering right now.")}
        </p>

        <div class="mt-3 flex flex-wrap items-center justify-between gap-2 text-sm">
          <span id="moderation-counts" class="opacity-80">
            {gettext("Waiting: %{pending} · To review: %{review}",
              pending: @moderation_counts.pending,
              review: @moderation_counts.review
            )}
            <.link :if={@moderation_counts.review > 0} navigate={~p"/admin/photos"} class="underline">
              {gettext("Review")}
            </.link>
          </span>
          <.button
            id="moderation-recheck"
            size="small"
            variant="bordered"
            color="natural"
            phx-click="moderation_recheck"
            data-confirm={gettext("Check every photo again with the level in use?")}
          >
            {gettext("Check all photos again")}
          </.button>
        </div>
      </.card>

      <.card id="services" padding="medium" rounded="large" class="mt-6 max-w-xl">
        <h2 class="flex items-center gap-1.5 font-semibold">
          {gettext("Outside services")}
          <.info_tip id="services-info">
            {gettext(
              "Services BASA uses but can't guarantee. Switch one off when it fails or isn't wanted: contracts keep working from booking to closing, on the parties' word in BASA."
            )}
          </.info_tip>
        </h2>
        <ul class="mt-2 divide-y divide-gray-200 dark:divide-gray-700">
          <li
            :for={service <- Basa.Services.all()}
            id={"service-#{service}"}
            class="flex items-center justify-between gap-4 py-3"
          >
            <% {name, gives, off} = texts(service) %>
            <h3 class="flex items-center gap-1.5 font-medium">
              {name}
              <.info_tip id={"service-#{service}-info"}>
                <span class="block">{gives}</span>
                <span class="mt-1 block">{gettext("When off:")} {off}</span>
              </.info_tip>
            </h3>
            <%= cond do %>
              <% not Basa.Services.configured?(service) -> %>
                <.badge id={"service-#{service}-unset"} size="extra_small" rounded="full">
                  {gettext("Not set up")}
                </.badge>
              <% service in @settings.services_off -> %>
                <.button
                  id={"service-#{service}-toggle"}
                  size="small"
                  variant="bordered"
                  color="natural"
                  phx-click="service"
                  phx-value-service={service}
                  phx-value-on="true"
                >
                  {gettext("Off")}
                </.button>
              <% true -> %>
                <.button
                  id={"service-#{service}-toggle"}
                  size="small"
                  variant="default"
                  color="success"
                  phx-click="service"
                  phx-value-service={service}
                  phx-value-on="false"
                >
                  {gettext("On")}
                </.button>
            <% end %>
          </li>
        </ul>
      </.card>
    </Layouts.app>
    """
  end
end
