defmodule BasaWeb.My.ImportLive do
  use BasaWeb, :live_view

  alias Basa.Import

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(page_title: gettext("Import from web pages")) |> load()}
  end

  defp load(socket) do
    user = socket.assigns.current_user
    status = if Import.enabled?(), do: Import.status(user), else: :off

    sources =
      if status == :ok,
        do:
          Import.list_sources!(
            actor: user,
            query: [filter: [owner_id: user.id], sort: [inserted_at: :desc]]
          ),
        else: []

    assign(socket, status: status, agreement: Import.current_agreement(), sources: sources)
  end

  @impl true
  def handle_event("confirm", %{"version" => version} = params, socket) do
    with "true" <- params["read"],
         {:ok, _} <-
           Import.accept_agreement(
             Import.access_for(socket.assigns.current_user),
             String.to_integer(version),
             actor: socket.assigns.current_user
           ) do
      {:noreply,
       socket |> put_flash(:info, gettext("Thank you. The import tool is open.")) |> load()}
    else
      "false" ->
        {:noreply,
         put_flash(socket, :error, gettext("Tick the box to confirm you read the agreement."))}

      nil ->
        {:noreply,
         put_flash(socket, :error, gettext("Tick the box to confirm you read the agreement."))}

      {:error, _} ->
        {:noreply,
         socket
         |> put_flash(:error, gettext("The agreement changed. Please read the new version."))
         |> load()}
    end
  end

  def handle_event("create", %{"source" => params}, socket) do
    urls =
      (params["urls"] || "")
      |> String.split(~r/\s+/, trim: true)
      |> Enum.uniq()

    case Import.create_source(%{name: params["name"], sample_urls: urls},
           actor: socket.assigns.current_user
         ) do
      {:ok, source} ->
        {:noreply, push_navigate(socket, to: ~p"/my/import/#{source.id}")}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, Enum.join(BasaWeb.ErrorText.messages(error), "; "))}
    end
  end

  defp host(source), do: source.sample_urls |> List.first("") |> URI.parse() |> Map.get(:host)

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} unread={@unread_count}>
      <.page_title title={gettext("Import from web pages")} info_id="import-info" help="import">
        <:info>
          {gettext(
            "Point BASA to pages of a site you list from: it finds the name, price, photos and details, and you pick what it missed. Imported listings stay drafts until you review them."
          )}
        </:info>
      </.page_title>

      <div :if={@status == :off} id="import-off">
        <.empty_state title={gettext("Import from web pages is switched off for now.")} />
      </div>

      <div :if={@status == :none} id="import-none">
        <.empty_state title={
          gettext("The import tool opens on request: ask the BASA administrator for access.")
        } />
      </div>

      <div :if={@status == :no_agreement} id="import-no-agreement">
        <.empty_state title={
          gettext("Your access is ready; the user agreement will be published soon.")
        } />
      </div>

      <.card :if={@status == :confirm} id="import-agreement" padding="medium" rounded="large">
        <h2 class="mb-2 font-semibold">
          {gettext("User agreement")}
          <span class="text-sm font-normal opacity-60">{gettext("version %{v}", v: @agreement.version)}</span>
        </h2>
        <div class="mb-4 max-h-80 overflow-y-auto whitespace-pre-line rounded-lg border border-zinc-200 p-3 text-sm dark:border-zinc-800">
          {@agreement.body}
        </div>
        <form id="agreement-confirm" phx-submit="confirm" class="space-y-3">
          <input type="hidden" name="version" value={@agreement.version} />
          <.checkbox_field
            id="agreement-read"
            name="read"
            value="true"
            label={gettext("I have read the agreement and accept it")}
          />
          <.button type="submit" color="primary" variant="default">{gettext("Confirm")}</.button>
        </form>
      </.card>

      <div :if={@status == :ok} class="space-y-6">
        <section>
          <.empty_state :if={@sources == []} title={gettext("No sources yet.")} />
          <div class="space-y-2">
            <.link
              :for={s <- @sources}
              id={"source-#{s.id}"}
              navigate={~p"/my/import/#{s.id}"}
              class="block"
            >
              <.card padding="small" rounded="large" class="hover:border-primary-light">
                <p class="font-medium">{s.name}</p>
                <p class="text-xs opacity-60">
                  {host(s)} · {ngettext(
                    "1 sample page",
                    "%{count} sample pages",
                    length(s.sample_urls)
                  )}
                </p>
              </.card>
            </.link>
          </div>
        </section>

        <.card padding="medium" rounded="large">
          <h2 class="mb-2 font-semibold">{gettext("New source")}</h2>
          <form id="source-form" phx-submit="create" class="space-y-3">
            <.text_field
              id="source-name"
              name="source[name]"
              value=""
              label={gettext("Name")}
              size="medium"
            />
            <.textarea_field
              id="source-urls"
              name="source[urls]"
              value=""
              rows="4"
              label={gettext("Sample pages, one address per line (up to 5)")}
              placeholder="https://"
            />
            <.button type="submit" color="primary" variant="default">{gettext("Create")}</.button>
          </form>
        </.card>
      </div>
    </Layouts.app>
    """
  end
end
