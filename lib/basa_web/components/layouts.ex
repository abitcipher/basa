defmodule BasaWeb.Layouts do
  use BasaWeb, :html

  embed_templates "layouts/*"

  attr :flash, :map, required: true
  attr :current_user, :map, default: nil
  attr :wide, :boolean, default: false, doc: "use the full content width"

  attr :active, :atom,
    default: nil,
    doc: ":find | :bookings | :messages | :my, highlights the dock item"

  attr :unread, :integer, default: 0, doc: "conversations with unread messages"
  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <header class="basa-header sticky top-0 z-30 border-b border-zinc-200 bg-white/90 backdrop-blur dark:border-zinc-800 dark:bg-zinc-900/90">
      <div class="mx-auto flex h-14 max-w-6xl items-center gap-4 px-4 sm:px-6">
        <.link navigate={~p"/"} class="flex items-center gap-2 text-xl font-black tracking-tight">
          <img src={~p"/images/logo.svg"} alt="" class="size-8  dark:hidden" />
          <img src={~p"/images/logo-dark.svg"} alt="" class="hidden size-8  dark:block" /> BASA
        </.link>
        <nav class="hidden gap-1 md:flex">
          <.button_link :if={@current_user} navigate={~p"/"} variant="transparent" size="small">
            {gettext("Find")}
          </.button_link>
          <.button_link
            :if={@current_user}
            navigate={~p"/bookings"}
            variant="transparent"
            size="small"
          >
            {gettext("Bookings")}
          </.button_link>
          <.button_link
            :if={@current_user}
            navigate={~p"/messages"}
            variant="transparent"
            size="small"
          >
            {gettext("Messages")}
            <.badge
              :if={@unread > 0}
              color="danger"
              size="extra_small"
              rounded="full"
              variant="default"
            >
              {@unread}
            </.badge>
          </.button_link>
          <.button_link :if={@current_user} navigate={~p"/my"} variant="transparent" size="small">
            {gettext("My offers")}
          </.button_link>
        </nav>
        <div class="ml-auto flex items-center gap-2">
          <.locale_switcher />
          <div class="hidden sm:block" data-theme-switch><.theme_toggle /></div>
          <%= if @current_user do %>
            <.dropdown
              id="user-menu"
              relative="relative"
              clickable
              position="bottom"
              rounded="large"
              padding="small"
              space="small"
            >
              <:trigger>
                <button type="button" aria-label={gettext("Account")} class="cursor-pointer">
                  <.avatar size="extra_small" rounded="full" color="dark">
                    <span class="text-xs font-semibold">{initials(@current_user)}</span>
                  </.avatar>
                </button>
              </:trigger>
              <:content>
                <div class="min-w-44 space-y-1 text-sm">
                  <p class="px-2 py-1 font-semibold">{display_name(@current_user)}</p>
                  <.link
                    navigate={~p"/profile"}
                    class="block rounded px-2 py-1 hover:bg-zinc-100 dark:hover:bg-zinc-800"
                  >
                    {gettext("Profile")}
                  </.link>
                  <.link
                    navigate={~p"/appearance"}
                    class="block rounded px-2 py-1 hover:bg-zinc-100 dark:hover:bg-zinc-800"
                  >
                    {gettext("Appearance")}
                  </.link>
                  <.link
                    navigate={~p"/help"}
                    id="menu-help"
                    class="block rounded px-2 py-1 hover:bg-zinc-100 dark:hover:bg-zinc-800"
                  >
                    {gettext("Help")}
                  </.link>
                  <.link
                    href={~p"/sign-out"}
                    class="block rounded px-2 py-1 hover:bg-zinc-100 dark:hover:bg-zinc-800"
                  >
                    {gettext("Sign out")}
                  </.link>
                </div>
              </:content>
            </.dropdown>
          <% else %>
            <.link navigate={~p"/help"} id="header-help" class="text-sm opacity-80 hover:opacity-100">
              {gettext("Help")}
            </.link>
            <.button_link navigate={~p"/sign-in"} color="primary" variant="default" size="small">
              {gettext("Sign in")}
            </.button_link>
          <% end %>
        </div>
      </div>
    </header>

    <main
      id="app-main"
      data-glow={glow(@current_user)}
      class={[
        "mx-auto px-4 pt-6 pb-[calc(7rem+env(safe-area-inset-bottom))] sm:px-6 md:pb-12",
        if(@wide, do: "max-w-6xl", else: "max-w-3xl")
      ]}
    >
      {render_slot(@inner_block)}
    </main>

    <div class="md:hidden">
      <.dock
        id="bottom-dock"
        position="fixed_bottom"
        show_labels
        color="natural"
        class="basa-dock z-30 pb-[env(safe-area-inset-bottom)]"
      >
        <:item
          icon="hero-magnifying-glass"
          label={gettext("Find")}
          navigate={~p"/"}
          active={@active == :find}
        />
        <:item
          icon="hero-calendar-days"
          label={gettext("Bookings")}
          navigate={~p"/bookings"}
          active={@active == :bookings}
        />
        <:item
          icon="hero-chat-bubble-left-right"
          label={gettext("Messages")}
          navigate={~p"/messages"}
          active={@active == :messages}
          badge={if @unread > 0, do: to_string(@unread)}
        />
        <:item
          icon="hero-squares-plus"
          label={gettext("My offers")}
          navigate={~p"/my"}
          active={@active == :my}
        />
      </.dock>
    </div>

    <.flash_group flash={@flash} />
    """
  end

  def locale_switcher(assigns) do
    assigns =
      assign(assigns,
        locales: Basa.I18n.locales(),
        current: Gettext.get_locale(BasaWeb.Gettext)
      )

    ~H"""
    <.dropdown
      id="locale-menu"
      relative="relative"
      clickable
      position="bottom"
      rounded="large"
      padding="small"
    >
      <:trigger>
        <.button variant="transparent" size="small">
          <span class="flex items-center gap-1.5">
            <.flag code={@current} />
            {case List.keyfind(@locales, @current, 0) do
              {_, label, _} -> label
              nil -> "EN"
            end}
          </span>
        </.button>
      </:trigger>
      <:content>
        <div class="flex min-w-36 flex-col text-sm">
          <a
            :for={{code, label, name} <- @locales}
            href={"?locale=#{code}"}
            data-locale={code}
            lang={code}
            class={[
              "flex items-center gap-2 rounded px-2 py-1 hover:bg-zinc-100 dark:hover:bg-zinc-800",
              code == @current && "font-semibold"
            ]}
          >
            <.flag code={code} />
            <span class="flex-1">{name}</span><span class="opacity-50">{label}</span>
          </a>
        </div>
      </:content>
    </.dropdown>
    """
  end

  def display_name(user), do: user.display_name || (user.email && to_string(user.email)) || "BASA"

  defp initials(user) do
    user
    |> display_name()
    |> String.split(~r/[^\p{L}\p{N}]+/u, trim: true)
    |> Enum.take(2)
    |> Enum.map_join(&String.first/1)
    |> String.upcase()
  end

  attr :flash, :map, required: true
  attr :id, :string, default: "flash-group"

  def flash_group(assigns) do
    ~H"""
    <BasaWeb.Components.Alert.flash_group
      id={@id}
      flash={@flash}
      position=""
      class="fixed top-16 right-0 mr-2"
    />
    """
  end

  attr :code, :string, required: true

  def flag(assigns) do
    ~H"""
    <img
      src={~p"/images/flags/#{@code <> ".svg"}"}
      alt=""
      class="h-3.5 w-5 shrink-0 rounded-[2px] object-cover ring-1 ring-black/10 dark:ring-white/15"
    />
    """
  end

  def theme_toggle(assigns) do
    assigns =
      assign(assigns,
        themes: [
          {"system", "hero-computer-desktop-micro", gettext("System")},
          {"light", "hero-sun-micro", gettext("Light")},
          {"dark", "hero-moon-micro", gettext("Dark")}
        ]
      )

    ~H"""
    <.dropdown
      id="theme-menu"
      relative="relative"
      clickable
      position="bottom"
      rounded="large"
      padding="small"
    >
      <:trigger>
        <button
          type="button"
          aria-label={gettext("Theme")}
          class="flex cursor-pointer rounded-full p-1.5 opacity-80 hover:bg-zinc-100 hover:opacity-100 dark:hover:bg-zinc-800"
        >
          <.icon
            name="hero-computer-desktop-micro"
            class="hidden size-4 [[data-theme-source=system]_&]:block"
          />
          <.icon
            name="hero-sun-micro"
            class="hidden size-4 [[data-theme-source=user][data-theme=light]_&]:block"
          />
          <.icon
            name="hero-moon-micro"
            class="hidden size-4 [[data-theme-source=user][data-theme=dark]_&]:block"
          />
        </button>
      </:trigger>
      <:content>
        <div class="flex min-w-36 flex-col text-sm">
          <button
            :for={{theme, icon, label} <- @themes}
            type="button"
            phx-click={JS.dispatch("phx:set-theme")}
            data-phx-theme={theme}
            class="flex cursor-pointer items-center gap-2 rounded px-2 py-1 text-left hover:bg-zinc-100 dark:hover:bg-zinc-800"
          >
            <.icon name={icon} class="size-4" />{label}
          </button>
        </div>
      </:content>
    </.dropdown>
    """
  end

  defp glow(%{glow: false}), do: "off"
  defp glow(_user), do: "on"
end
