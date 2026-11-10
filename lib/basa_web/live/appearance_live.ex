defmodule BasaWeb.AppearanceLive do
  use BasaWeb, :live_view

  alias Basa.Accounts.UiPrefs

  @swatches %{
    "neutral" => "#71717a",
    "cyan" => "#00ccff",
    "green" => "#00d400",
    "yellow" => "#ffd42a",
    "orange" => "#ff7f2a"
  }

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(page_title: gettext("Appearance")) |> assign_prefs()}
  end

  defp assign_prefs(socket) do
    user = socket.assigns.current_user
    assign(socket, prefs: UiPrefs.get(user), glow: user.glow)
  end

  @impl true
  def handle_event("change", %{"ui" => ui} = params, socket) do
    save(socket, Map.merge(socket.assigns.prefs, ui), params["glow"] == "true")
  end

  def handle_event("reset", _params, socket), do: save(socket, UiPrefs.defaults(), true)

  defp save(socket, prefs, glow) do
    user = socket.assigns.current_user

    case Basa.Accounts.update_ui(user, %{ui: prefs, glow: glow}, actor: user) do
      {:ok, user} ->
        {:noreply,
         socket
         |> assign(current_user: user)
         |> assign_prefs()
         |> push_event("ui:apply", %{
           attrs: Map.new(UiPrefs.html_attrs(user)),
           glow: if(user.glow, do: "on", else: "off")
         })}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Could not save."))}
    end
  end

  defp style_label("brand"), do: gettext("Brand colours")
  defp style_label("black"), do: gettext("Black")
  defp style_label("white"), do: gettext("White")

  defp colour_label("neutral"), do: gettext("Neutral")
  defp colour_label("cyan"), do: gettext("Cyan")
  defp colour_label("green"), do: gettext("Green")
  defp colour_label("yellow"), do: gettext("Yellow")
  defp colour_label("orange"), do: gettext("Orange")

  defp disabled_label("tint"), do: gettext("Soft colour")
  defp disabled_label("gray"), do: gettext("Gray")

  @impl true
  def render(assigns) do
    assigns =
      assign(assigns, choices: UiPrefs.choices(), scales: UiPrefs.scales(), swatches: @swatches)

    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} unread={@unread_count}>
      <div id="appearance" phx-hook="UiApply">
        <div class="mb-4 flex items-center gap-2">
          <.back_button navigate={~p"/profile"} label={gettext("Profile")} />
          <h1 class="text-xl font-bold">{gettext("Appearance")}</h1>
        </div>

        <div class="grid gap-4 md:grid-cols-[1fr_17rem]">
          <form id="appearance-form" phx-change="change" class="space-y-5">
            <.setting title={gettext("Buttons")}>
              <.segmented
                name="ui[style]"
                options={@choices["style"]}
                value={@prefs["style"]}
                label={&style_label/1}
              />
            </.setting>

            <.setting
              title={gettext("Action buttons")}
              hint={gettext("Send, save, book: the main thing on a page.")}
              muted={@prefs["style"] != "brand"}
            >
              <.swatches
                name="ui[action]"
                options={@choices["action"]}
                value={@prefs["action"]}
                swatches={@swatches}
                label={&colour_label/1}
              />
            </.setting>

            <.setting
              title={gettext("Navigation buttons")}
              hint={gettext("Back, details, tabs: moving around.")}
              muted={@prefs["style"] != "brand"}
            >
              <.swatches
                name="ui[nav]"
                options={@choices["nav"]}
                value={@prefs["nav"]}
                swatches={@swatches}
                label={&colour_label/1}
              />
            </.setting>

            <.setting title={gettext("Disabled buttons")}>
              <.segmented
                name="ui[disabled]"
                options={@choices["disabled"]}
                value={@prefs["disabled"]}
                label={&disabled_label/1}
              />
            </.setting>

            <.setting title={gettext("Size")}>
              <div class="space-y-3">
                <.slider
                  name="ui[button]"
                  label={gettext("Buttons")}
                  value={@prefs["button"]}
                  range={@scales["button"]}
                />
                <.slider
                  name="ui[icon]"
                  label={gettext("Icons")}
                  value={@prefs["icon"]}
                  range={@scales["icon"]}
                />
                <.slider
                  name="ui[text]"
                  label={gettext("Text")}
                  value={@prefs["text"]}
                  range={@scales["text"]}
                />
              </div>
            </.setting>

            <.setting
              title={gettext("Card glow")}
              hint={gettext("Cards light up in colour near the mouse pointer.")}
            >
              <input type="hidden" name="glow" value="false" />
              <label class="inline-flex cursor-pointer items-center gap-2 text-sm">
                <input type="checkbox" name="glow" value="true" checked={@glow} class="peer sr-only" />
                <span class="relative h-5 w-9 rounded-full bg-zinc-300 transition after:absolute after:top-0.5 after:left-0.5 after:size-4 after:rounded-full after:bg-white after:transition peer-checked:bg-[var(--ui-action)] peer-checked:after:translate-x-4 dark:bg-zinc-700"></span>
                {if @glow, do: gettext("On"), else: gettext("Off")}
              </label>
            </.setting>

            <button
              type="button"
              phx-click="reset"
              class="text-sm underline opacity-70 hover:opacity-100"
            >
              {gettext("Back to defaults")}
            </button>
          </form>

          <aside class="md:sticky md:top-20 md:self-start">
            <.card padding="medium" rounded="large">
              <p class="mb-3 text-xs font-semibold tracking-wide uppercase opacity-60">
                {gettext("Preview")}
              </p>
              <div class="flex flex-wrap items-center gap-2">
                <.button color="primary" variant="default" icon="hero-check">{gettext("Save")}</.button>
                <.button color="primary" variant="bordered">{gettext("Book")}</.button>
                <.button_link navigate="#" variant="bordered" icon="hero-photo">{gettext("Photos")}</.button_link>
                <.button_link navigate="#" variant="transparent">{gettext("Details")}</.button_link>
              </div>
              <div class="mt-3 flex flex-wrap items-center gap-2">
                <.button color="primary" variant="default" disabled>{gettext("Save")}</.button>
                <.button variant="bordered" disabled>{gettext("Details")}</.button>
              </div>
              <div class="mt-3 flex items-center gap-2">
                <.back_button navigate="#" label={gettext("Back")} />
                <button
                  type="button"
                  class="basa-round-btn flex size-11 items-center justify-center rounded-full shadow-sm"
                  aria-label={gettext("Send")}
                >
                  <.brand_icon name="right" class="size-5 translate-x-px" />
                </button>
                <button
                  type="button"
                  disabled
                  class="basa-round-btn flex size-11 items-center justify-center rounded-full"
                  aria-label={gettext("Send")}
                >
                  <.brand_icon name="right" class="size-5 translate-x-px" />
                </button>
              </div>
            </.card>
          </aside>
        </div>
      </div>
    </Layouts.app>
    """
  end

  attr :title, :string, required: true
  attr :hint, :string, default: nil
  attr :muted, :boolean, default: false
  slot :inner_block, required: true

  defp setting(assigns) do
    ~H"""
    <section class={["transition-opacity", @muted && "opacity-40"]}>
      <h2 class="text-sm font-semibold">{@title}</h2>
      <p :if={@hint} class="mb-2 text-xs opacity-60">{@hint}</p>
      <div class={!@hint && "mt-2"}>{render_slot(@inner_block)}</div>
    </section>
    """
  end

  attr :name, :string, required: true
  attr :options, :list, required: true
  attr :value, :string, required: true
  attr :label, :any, required: true

  defp segmented(assigns) do
    ~H"""
    <div class="inline-flex rounded-full bg-zinc-100 p-1 dark:bg-zinc-800" role="radiogroup">
      <label :for={o <- @options} class="cursor-pointer">
        <input type="radio" name={@name} value={o} checked={o == @value} class="peer sr-only" />
        <span class="block rounded-full px-3.5 py-1.5 text-sm opacity-70 transition peer-checked:bg-white peer-checked:font-medium peer-checked:opacity-100 peer-checked:shadow-sm peer-focus-visible:ring-2 peer-focus-visible:ring-primary-light dark:peer-checked:bg-zinc-950">
          {@label.(o)}
        </span>
      </label>
    </div>
    """
  end

  attr :name, :string, required: true
  attr :options, :list, required: true
  attr :value, :string, required: true
  attr :swatches, :map, required: true
  attr :label, :any, required: true

  defp swatches(assigns) do
    ~H"""
    <div class="flex flex-wrap gap-2" role="radiogroup">
      <label :for={o <- @options} class="cursor-pointer" title={@label.(o)}>
        <input type="radio" name={@name} value={o} checked={o == @value} class="peer sr-only" />
        <span class="flex items-center gap-1.5 rounded-full border border-zinc-200 py-1 pr-3 pl-1 text-xs transition peer-checked:border-transparent peer-checked:ring-2 peer-checked:ring-zinc-900 peer-focus-visible:ring-2 dark:border-zinc-700 dark:peer-checked:ring-zinc-100">
          <span class="size-5 rounded-full" style={"background: #{@swatches[o]}"}></span>
          {@label.(o)}
        </span>
      </label>
    </div>
    """
  end

  attr :name, :string, required: true
  attr :label, :string, required: true
  attr :value, :integer, required: true
  attr :range, :any, required: true

  defp slider(assigns) do
    {lo, hi} = assigns.range
    assigns = assign(assigns, lo: lo, hi: hi)

    ~H"""
    <label class="grid grid-cols-[6rem_1fr_3rem] items-center gap-3 text-sm">
      <span class="opacity-80">{@label}</span>
      <input
        type="range"
        name={@name}
        min={@lo}
        max={@hi}
        step="5"
        value={@value}
        phx-debounce="150"
        class="w-full accent-[var(--ui-action)]"
      />
      <span class="text-right font-mono text-xs opacity-70">{@value}%</span>
    </label>
    """
  end
end
