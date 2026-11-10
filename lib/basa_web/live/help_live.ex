defmodule BasaWeb.HelpLive do
  use BasaWeb, :live_view

  alias BasaWeb.Help

  @impl true
  def mount(_params, _session, socket), do: {:ok, socket}

  @impl true
  def handle_params(%{"topic" => topic}, _uri, socket) do
    case Help.page(topic, locale()) do
      {:ok, page} ->
        {:noreply, assign(socket, page_title: page.title, page: page, topic: topic)}

      :error ->
        {:noreply,
         socket |> put_flash(:error, gettext("No such help page.")) |> push_patch(to: ~p"/help")}
    end
  end

  def handle_params(_params, _uri, socket),
    do: {:noreply, assign(socket, page_title: gettext("Help"), page: nil, topic: nil)}

  defp locale, do: Gettext.get_locale(BasaWeb.Gettext)

  defp group_title(:renters), do: gettext("Renting")
  defp group_title(:owners), do: gettext("Offering your space or gear")
  defp group_title(:everyone), do: gettext("Your account")
  defp group_title(:admins), do: gettext("For admins")

  defp admin?(%{role: :admin}), do: true
  defp admin?(_), do: false

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} unread={@unread_count}>
      <div :if={!@page} id="help-index" class="max-w-2xl">
        <.page_title title={gettext("Help")} />
        <section
          :for={{group, topics} <- Help.groups()}
          :if={group != :admins or admin?(@current_user)}
          class="mb-6"
        >
          <h2 class="mb-2 font-semibold">{group_title(group)}</h2>
          <ul class="space-y-1">
            <li :for={topic <- topics}>
              <.link patch={~p"/help/#{topic}"} id={"help-#{topic}"} class="underline">
                {Help.title(topic, locale())}
              </.link>
            </li>
          </ul>
        </section>
      </div>

      <article :if={@page} id={"help-page-#{@topic}"} class="max-w-2xl">
        <.back_button patch={~p"/help"} label={gettext("Help")} />
        <h1 class="mt-2 mb-3 text-2xl font-bold">{@page.title}</h1>
        <p :if={@page.language != locale()} id="help-in-english" class="mb-3 text-sm opacity-70">
          {gettext("This page is not in your language yet; here it is in English.")}
        </p>
        <div class="basa-help">{Phoenix.HTML.raw(@page.html)}</div>
      </article>
    </Layouts.app>
    """
  end
end
