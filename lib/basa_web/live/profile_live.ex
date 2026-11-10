defmodule BasaWeb.ProfileLive do
  use BasaWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    user =
      Ash.load!(socket.assigns.current_user, :has_password, actor: socket.assigns.current_user)

    {:ok,
     assign(socket,
       page_title: gettext("Profile"),
       bot: Basa.Telegram.enabled?() && Basa.Telegram.username(),
       user: user,
       password_error: nil,
       new_key: nil
     )
     |> load_keys()}
  end

  defp load_keys(socket) do
    keys =
      Basa.Accounts.list_api_keys!(
        actor: socket.assigns.current_user,
        query: [sort: [inserted_at: :desc]]
      )

    assign(socket, api_keys: keys)
  end

  @key_days %{"30" => 30, "90" => 90, "365" => 365}

  @impl true
  def handle_event("create_key", %{"key" => params}, socket) do
    days = Map.get(@key_days, params["days"], 90)
    expires = DateTime.add(DateTime.utc_now(), days, :day)

    case Basa.Accounts.create_api_key(params["name"], expires, actor: socket.assigns.current_user) do
      {:ok, key} ->
        {:noreply, socket |> assign(new_key: key.__metadata__.plaintext_api_key) |> load_keys()}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, Enum.join(BasaWeb.ErrorText.messages(error), "; "))}
    end
  end

  def handle_event("revoke_key", %{"id" => id}, socket) do
    key = Enum.find(socket.assigns.api_keys, &(&1.id == id))
    :ok = Basa.Accounts.revoke_api_key(key, actor: socket.assigns.current_user)

    {:noreply,
     socket |> assign(new_key: nil) |> put_flash(:info, gettext("Key revoked.")) |> load_keys()}
  end

  def handle_event("hide_key", _params, socket), do: {:noreply, assign(socket, new_key: nil)}

  def handle_event("add_password", %{"sign_in" => params}, socket) do
    user = socket.assigns.user

    case Basa.Accounts.add_password_sign_in(user, params, actor: user) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> assign(user: Ash.load!(updated, :has_password, actor: updated), password_error: nil)
         |> put_flash(
           :info,
           gettext("Saved. You can now also sign in with your email and password.")
         )}

      {:error, error} ->
        {:noreply, assign(socket, password_error: password_error(error))}
    end
  end

  @impl true
  def handle_event("save", %{"profile" => params}, socket) do
    case Basa.Accounts.update_profile(socket.assigns.current_user, params,
           actor: socket.assigns.current_user
         ) do
      {:ok, user} ->
        {:noreply,
         socket
         |> assign(user: user, current_user: user)
         |> put_flash(:info, gettext("Saved."))
         |> redirect(to: ~p"/profile?locale=#{user.locale}")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Could not save."))}
    end
  end

  defp password_error(%Ash.Error.Invalid{errors: errors}) do
    cond do
      Enum.any?(errors, &(Map.get(&1, :field) == :email)) ->
        gettext("Check the email: it may be empty or already used by another account.")

      Enum.any?(errors, &(Map.get(&1, :field) == :password)) ->
        gettext("The password needs at least 8 characters.")

      true ->
        gettext("The passwords don't match.")
    end
  end

  defp password_error(_), do: gettext("Could not save.")

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} unread={@unread_count}>
      <.page_title title={gettext("Profile")} />

      <form id="profile-form" phx-submit="save" class="max-w-md space-y-4">
        <.text_field
          name="profile[display_name]"
          value={@user.display_name}
          label={gettext("Name shown to others")}
          size="medium"
        />
        <.native_select
          id="profile-locale"
          name="profile[locale]"
          label={gettext("Language")}
          size="medium"
        >
          <:option
            :for={{code, _label, name} <- Basa.I18n.locales()}
            value={code}
            selected={to_string(@user.locale) == code}
          >
            {name}
          </:option>
        </.native_select>
        <div class="flex flex-wrap items-center gap-3">
          <.button type="submit" color="primary" variant="default">{gettext("Save")}</.button>
          <.button_link navigate={~p"/appearance"} variant="bordered" icon="hero-swatch">
            {gettext("Appearance")}
          </.button_link>
        </div>
      </form>

      <.card padding="medium" rounded="large" class="mt-8 max-w-md space-y-3">
        <h2 class="font-semibold">{gettext("Contact")}</h2>
        <p :if={@user.email} class="flex items-center gap-2">
          <.icon name="hero-envelope" class="size-4" /> {@user.email}
        </p>
        <p class="flex flex-wrap items-center gap-2">
          <.icon name="hero-phone" class="size-4" />
          <%= if @user.phone_verified_at do %>
            {@user.phone}
            <.badge color="success" size="extra_small" rounded="full">{gettext("verified")}</.badge>
          <% else %>
            {gettext("Not verified.")}
            <.info_tip :if={@bot} id="phone-info">
              {gettext("Open the bot and tap “Share phone” to verify it through Telegram.")}
            </.info_tip>
          <% end %>
        </p>
        <p class="flex flex-wrap items-center gap-2">
          <.icon name="hero-paper-airplane" class="size-4" />
          <%= if @user.telegram_id do %>
            {gettext("Telegram connected")}
            <span :if={@user.telegram_username}>(@{@user.telegram_username})</span>
          <% else %>
            {gettext("Telegram not connected.")}
            <a :if={@bot} href={"https://t.me/#{@bot}"} class="underline" target="_blank">{gettext(
              "Open @%{bot}",
              bot: @bot
            )}</a>
          <% end %>
        </p>
      </.card>
      <.card
        :if={!@user.has_password}
        id="password-sign-in"
        padding="medium"
        rounded="large"
        class="mt-6 max-w-md"
      >
        <h2 class="mb-3 flex items-center gap-1.5 font-semibold">
          {gettext("Sign in without Telegram")}
          <.info_tip id="password-sign-in-info">
            {gettext(
              "Add an email and a password, so you can still sign in and reach your contracts when Telegram is unavailable."
            )}
          </.info_tip>
        </h2>
        <form id="password-sign-in-form" phx-submit="add_password" class="space-y-3">
          <.email_field
            id="sign-in-email"
            name="sign_in[email]"
            value={@user.email}
            label={gettext("Email")}
            size="medium"
          />
          <.password_field
            id="sign-in-password"
            name="sign_in[password]"
            label={gettext("Password")}
            size="medium"
          />
          <.password_field
            id="sign-in-password-confirmation"
            name="sign_in[password_confirmation]"
            label={gettext("Password again")}
            size="medium"
          />
          <p :if={@password_error} id="password-sign-in-error" class="text-sm text-red-600">
            {@password_error}
          </p>
          <.button type="submit" color="primary" variant="default">{gettext("Save")}</.button>
        </form>
      </.card>

      <.card id="api-keys" padding="medium" rounded="large" class="mt-6 max-w-md">
        <div class="mb-2 flex items-center gap-2">
          <h2 class="flex items-center gap-1.5 font-semibold">
            {gettext("API keys")} <.help_link topic="api-keys" />
          </h2>
          <.info_tip id="api-keys-info">
            {gettext(
              "For your own programs and shop systems: a key works like you on the BASA API (categories, your items). Send it as Authorization: Bearer and the key. It is shown once; keep it secret, and revoke it if it leaks."
            )}
          </.info_tip>
          <.link href={~p"/api/json/swaggerui"} target="_blank" class="ml-auto text-sm underline">
            {gettext("API documentation")}
          </.link>
        </div>

        <div :if={@new_key} id="new-api-key" class="mb-4 space-y-2">
          <p class="text-sm font-medium">{gettext("Your new key, shown only now:")}</p>
          <code
            id="new-api-key-text"
            class="block break-all rounded-lg bg-zinc-100 p-2 text-xs dark:bg-zinc-800"
          >{@new_key}</code>
          <div class="flex items-center gap-3">
            <.clipboard text={@new_key} id="new-api-key-copy" copy_success_text={gettext("Copied")}>
              <:trigger>
                <span class="cursor-pointer text-sm underline">{gettext("Copy")}</span>
              </:trigger>
            </.clipboard>
            <.button size="small" variant="bordered" phx-click="hide_key">{gettext("I saved it")}</.button>
          </div>
        </div>

        <form id="api-key-form" phx-submit="create_key" class="mb-4 flex flex-wrap items-end gap-2">
          <div class="min-w-0 flex-1">
            <.text_field
              id="api-key-name"
              name="key[name]"
              value=""
              label={gettext("Key name")}
              placeholder={gettext("Shop sync")}
              size="medium"
            />
          </div>
          <.native_select
            id="api-key-days"
            name="key[days]"
            label={gettext("Valid for")}
            size="medium"
          >
            <:option value="30">{gettext("30 days")}</:option>
            <:option value="90" selected>{gettext("90 days")}</:option>
            <:option value="365">{gettext("A year")}</:option>
          </.native_select>
          <.button type="submit" color="primary" variant="default">{gettext("Make a key")}</.button>
        </form>

        <div class="space-y-2">
          <div
            :for={k <- @api_keys}
            id={"api-key-#{k.id}"}
            class="flex items-center justify-between gap-2 text-sm"
          >
            <div class="min-w-0">
              <p class="truncate font-medium">{k.name}</p>
              <p class="text-xs opacity-60">
                {gettext("Valid until %{date}", date: Calendar.strftime(k.expires_at, "%Y-%m-%d"))} · {if k.last_used_at,
                  do:
                    gettext("last used %{date}", date: Calendar.strftime(k.last_used_at, "%Y-%m-%d")),
                  else: gettext("not used yet")}
              </p>
            </div>
            <.button
              size="small"
              variant="bordered"
              phx-click="revoke_key"
              phx-value-id={k.id}
              data-confirm={
                gettext("Revoke the key “%{name}”? Programs using it stop working.", name: k.name)
              }
            >
              {gettext("Revoke")}
            </.button>
          </div>
        </div>
      </.card>

      <.card :if={@current_user.role == :admin} padding="medium" rounded="large" class="mt-6 max-w-md">
        <h2 class="mb-2 font-semibold">{gettext("Admin")}</h2>
        <nav class="flex flex-wrap gap-2">
          <.button_link size="small" variant="bordered" navigate={~p"/admin/review"}>
            {gettext("Offer review")}
          </.button_link>
          <.button_link size="small" variant="bordered" navigate={~p"/admin/rules"}>
            {gettext("Rules")}
          </.button_link>
          <.button_link size="small" variant="bordered" navigate={~p"/admin/photos"}>
            {gettext("Photo checks")}
          </.button_link>
          <.button_link size="small" variant="bordered" navigate={~p"/admin/geo"}>
            {gettext("Cities")}
          </.button_link>
          <.button_link size="small" variant="bordered" navigate={~p"/admin/witness"}>
            {gettext("Contracts")}
          </.button_link>
          <.button_link size="small" variant="bordered" navigate={~p"/admin/data"}>
            {gettext("Data")}
          </.button_link>
          <.button_link size="small" variant="bordered" navigate={~p"/admin/import"}>
            {gettext("Import")}
          </.button_link>
          <.button_link size="small" variant="bordered" navigate={~p"/admin/settings"}>
            {gettext("Settings")}
          </.button_link>
        </nav>
      </.card>
    </Layouts.app>
    """
  end
end
