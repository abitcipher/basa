defmodule BasaWeb.SignInLive do
  use BasaWeb, :live_view

  alias AshAuthentication.Phoenix.Components
  alias Basa.Accounts.SignInMethods

  @impl true
  def mount(_params, session, socket) do
    {:ok,
     assign(socket,
       page_title: gettext("Sign in"),
       overrides: session["overrides"] || [AshAuthentication.Phoenix.Overrides.Default],
       path: session["path"] || "/",
       reset_path: session["reset_path"],
       register_path: session["register_path"],
       auth_routes_prefix: session["auth_routes_prefix"],
       gettext_fn: session["gettext_fn"],
       context: session["context"] || %{},
       password: AshAuthentication.Info.strategy!(Basa.Accounts.User, :password),
       methods: SignInMethods.available()
     )}
  end

  @impl true
  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto flex min-h-screen max-w-sm flex-col justify-center px-4 py-10">
      <.link navigate={~p"/"} class="mx-auto mb-9 block w-fit" aria-label="BASA">
        <img src={~p"/images/logo-transparent.svg"} alt="BASA" class="size-24 dark:hidden" />
        <img src={~p"/images/logo-transparent.svg"} alt="BASA" class="hidden size-24 dark:block" />
      </.link>

      <.live_component
        module={Components.Password}
        id="user-password"
        strategy={@password}
        auth_routes_prefix={@auth_routes_prefix}
        path={@path}
        reset_path={@reset_path}
        register_path={@register_path}
        live_action={@live_action}
        overrides={@overrides}
        current_tenant={nil}
        context={@context}
        gettext_fn={@gettext_fn}
      />

      <div :if={@methods != [] and @live_action == :sign_in} id="sign-in-methods" class="mt-6">
        <div class="mb-4 flex items-center gap-3 text-xs opacity-60">
          <span class="h-px flex-1 bg-zinc-300 dark:bg-zinc-700"></span>
          {gettext("or")}
          <span class="h-px flex-1 bg-zinc-300 dark:bg-zinc-700"></span>
        </div>
        <div class="space-y-2">
          <.method :for={method <- @methods} method={method} />
        </div>
      </div>
    </div>
    """
  end

  attr :method, :atom, required: true

  defp method(%{method: :telegram} = assigns) do
    assigns =
      assign(assigns,
        emulator?: Basa.Telegram.emulator?(),
        bot: Basa.Telegram.username()
      )

    ~H"""
    <.button_link
      :if={@emulator?}
      id="sign-in-telegram"
      navigate="/dev/telegram"
      variant="bordered"
      class="w-full justify-center"
    >
      <.method_icon method={:telegram} /> {gettext("Sign in with Telegram")}
    </.button_link>
    <div
      :if={!@emulator?}
      id="sign-in-telegram"
      phx-update="ignore"
      class="flex justify-center"
    >
      <script
        async
        src="https://telegram.org/js/telegram-widget.js?22"
        data-telegram-login={@bot}
        data-size="large"
        data-radius="8"
        data-auth-url={url(~p"/auth/telegram/widget")}
        data-request-access="write"
      >
      </script>
    </div>
    """
  end

  defp method(assigns) do
    ~H"""
    <.button_link
      id={"sign-in-#{@method}"}
      href={"/auth/user/#{@method}"}
      variant="bordered"
      class="w-full justify-center"
    >
      <.method_icon method={@method} /> {label(@method)}
    </.button_link>
    """
  end

  defp label(:google), do: gettext("Sign in with Google")
  defp label(:facebook), do: gettext("Sign in with Facebook")
  defp label(:instagram), do: gettext("Sign in with Instagram")

  attr :method, :atom, required: true

  defp method_icon(%{method: :google} = assigns),
    do: ~H"""
    <span class="font-bold text-[#4285F4]" aria-hidden="true">G</span>
    """

  defp method_icon(%{method: :facebook} = assigns),
    do: ~H"""
    <span class="font-bold text-[#1877F2]" aria-hidden="true">f</span>
    """

  defp method_icon(%{method: :instagram} = assigns),
    do: ~H"""
    <.icon name="hero-camera" class="size-4 text-[#E1306C]" />
    """

  defp method_icon(%{method: :telegram} = assigns),
    do: ~H"""
    <.icon name="hero-paper-airplane" class="size-4 text-[#26A5E4]" />
    """
end
