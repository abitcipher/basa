defmodule BasaWeb.Admin.RulesLive do
  use BasaWeb, :live_view

  alias Basa.Rules

  @impl true
  def mount(_params, _session, socket) do
    if socket.assigns.current_user.role == :admin do
      Basa.Rules.Library.sync()

      {:ok,
       socket
       |> assign(page_title: gettext("Rules"))
       |> load()}
    else
      {:ok, socket |> put_flash(:error, gettext("Admins only.")) |> push_navigate(to: ~p"/")}
    end
  end

  defp load(socket),
    do:
      assign(socket,
        rules: Rules.list_rule_sets!(actor: socket.assigns.current_user) |> Enum.sort_by(& &1.key)
      )

  @impl true
  def handle_event("configure", %{"key" => key} = params, socket) do
    rule = Enum.find(socket.assigns.rules, &(&1.key == key))

    attrs =
      %{}
      |> then(
        &if(params["severity"],
          do: Map.put(&1, :severity, String.to_existing_atom(params["severity"])),
          else: &1
        )
      )
      |> then(
        &if(params["enabled"], do: Map.put(&1, :enabled, params["enabled"] == "true"), else: &1)
      )

    Rules.configure_rule_set!(rule, attrs, actor: socket.assigns.current_user)
    {:noreply, socket |> put_flash(:info, gettext("Saved.")) |> load()}
  end

  def sample_context(_rule \\ nil) do
    %{
      "point" => "lot.submit",
      "subject" => "lot",
      "lot" => %{
        "title" => "Vocal studio",
        "titleLength" => 12,
        "priceAmount" => 450.0,
        "currency" => "UAH",
        "priceUnit" => "hour",
        "itemCount" => 1,
        "attendantCount" => 1,
        "totalValue" => 120_000.0,
        "hasRoom" => true,
        "roomHasLocation" => true,
        "city" => "Odesa",
        "mobile" => false
      }
    }
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} unread={@unread_count} wide>
      <.page_title title={gettext("Rules")} info_id="rules-info">
        <:info>
          {gettext(
            "Checks run when an offer is submitted. Block: back to draft with the reason. Flag: an admin reviews it. Observe: recorded only."
          )}
        </:info>
      </.page_title>

      <div class="space-y-2">
        <.card :for={rule <- @rules} padding="small" rounded="large">
          <div class="flex flex-wrap items-center justify-between gap-3">
            <div class="min-w-0">
              <p class="font-medium">
                {rule.label} <span class="text-xs opacity-50">{rule.key} · v{rule.version}</span>
              </p>
              <p class="text-sm opacity-70">{rule.description}</p>
              <p :if={rule.updated_by_email} class="text-xs opacity-50">
                {gettext("Edited by %{who}", who: rule.updated_by_email)}
              </p>
            </div>
            <div class="flex items-center gap-2">
              <form id={"severity-#{rule.key}"} phx-change="configure">
                <input type="hidden" name="key" value={rule.key} />
                <.native_select id={"sev-#{rule.key}"} name="severity" size="small">
                  <:option
                    :for={s <- [:block, :flag, :observe]}
                    value={s}
                    selected={rule.severity == s}
                  >
                    {s}
                  </:option>
                </.native_select>
              </form>
              <.button
                size="small"
                variant={if rule.enabled, do: "default", else: "bordered"}
                color={if rule.enabled, do: "success", else: "natural"}
                phx-click="configure"
                phx-value-key={rule.key}
                phx-value-enabled={to_string(!rule.enabled)}
              >
                {if rule.enabled, do: gettext("On"), else: gettext("Off")}
              </.button>
              <.button_link
                id={"edit-#{rule.key}"}
                size="small"
                variant="bordered"
                navigate={~p"/admin/rules/#{rule.key}"}
              >
                {gettext("Edit")}
              </.button_link>
            </div>
          </div>
        </.card>
      </div>
    </Layouts.app>
    """
  end
end
