defmodule BasaWeb.Admin.RuleEditorLive do
  use BasaWeb, :live_view

  alias Basa.Rules
  alias RulesEngine, as: Engine

  @impl true
  def mount(%{"key" => key}, _session, socket) do
    user = socket.assigns.current_user

    with :admin <- user.role,
         {:ok, rule} <- Rules.get_rule_set(key, actor: user) do
      {:ok,
       assign(socket,
         page_title: rule.label,
         rule: rule,
         dirty?: false,
         context_json: Jason.encode!(BasaWeb.Admin.RulesLive.sample_context(rule), pretty: true)
       )}
    else
      _ -> {:ok, socket |> put_flash(:error, gettext("Admins only.")) |> push_navigate(to: ~p"/")}
    end
  end

  @impl true
  def handle_event("changed", _params, socket), do: {:noreply, assign(socket, dirty?: true)}

  def handle_event("json_error", %{"message" => message}, socket),
    do:
      {:noreply,
       put_flash(socket, :error, gettext("The JSON isn't valid: %{error}", error: message))}

  def handle_event("save_graph", %{"graph" => graph}, socket) do
    case Rules.update_rule_graph(socket.assigns.rule, graph, actor: socket.assigns.current_user) do
      {:ok, rule} ->
        {:noreply,
         socket
         |> assign(rule: rule, dirty?: false)
         |> push_event("rules:saved", %{})
         |> put_flash(:info, gettext("Saved as version %{v}.", v: rule.version))}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, Enum.join(BasaWeb.ErrorText.messages(error), "; "))}
    end
  end

  def handle_event("simulate", %{"graph" => graph, "context" => context_json}, socket) do
    reply =
      with {:ok, context} <- Jason.decode(context_json),
           {:ok, response} <- Engine.simulate(graph, context) do
        %{result: Map.put(response, "snapshot", graph)}
      else
        {:error, %Jason.DecodeError{} = e} ->
          %{error: %{title: gettext("Test input"), message: Exception.message(e), data: %{}}}

        {:error, reason} ->
          %{
            error: %{
              title: gettext("Rule error"),
              message: error_text(reason),
              data: %{nodeId: node_id(reason)}
            }
          }
      end

    {:reply, %{simulate: reply}, assign(socket, context_json: context_json)}
  end

  defp error_text(%{"message" => m}), do: m
  defp error_text(%{"type" => t} = e), do: "#{t}: #{inspect(Map.drop(e, ["type"]))}"
  defp error_text(other), do: inspect(other)

  defp node_id(%{"nodeId" => id}), do: id
  defp node_id(%{"source" => %{"nodeId" => id}}), do: id
  defp node_id(_), do: nil

  defp select(tab), do: JS.dispatch("rules:tab", to: "#rules-editor", detail: %{tab: tab})

  defp show_js(tab), do: hide_tab("rules-tabs", 3) |> show_tab("rules-tabs", tab)

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} unread={@unread_count} wide>
      <div class="mb-3 flex flex-wrap items-center justify-between gap-2">
        <div>
          <.back_button navigate={~p"/admin/rules"} label={gettext("Rules")} class="mb-1" />
          <h1 class="text-xl font-bold">
            {@rule.label}
            <span class="text-sm font-normal opacity-50">{@rule.key} · v{@rule.version}</span>
          </h1>
        </div>
        <div class="flex items-center gap-2">
          <span :if={@dirty?} class="text-sm opacity-70">{gettext("Unsaved changes")}</span>
          <.info_tip id="rules-test-info" align="end">
            {gettext(
              "Test runs the rule on the test input and shows the results on the graph: open a node to see what it received and returned."
            )}
          </.info_tip>
          <.button
            id="rules-test"
            variant="bordered"
            phx-click={JS.dispatch("rules:simulate", to: "#rules-editor")}
          >
            {gettext("Test")}
          </.button>
          <.button
            id="rules-save"
            color="primary"
            variant="default"
            phx-click={JS.dispatch("rules:save", to: "#rules-editor")}
          >
            {gettext("Save new version")}
          </.button>
        </div>
      </div>

      <div
        id="rules-editor"
        phx-hook="RulesEditor"
        data-graph={Jason.encode!(@rule.graph)}
        data-context={@context_json}
        data-show-1={show_js(1)}
        data-show-2={show_js(2)}
        data-show-3={show_js(3)}
      >
        <.tabs
          id="rules-tabs"
          variant="nav_pills"
          color="primary"
          padding="small"
          content_padding="none"
        >
          <:tab icon="hero-share" active on_select={select(1)}>{gettext("Graph")}</:tab>
          <:tab icon="hero-code-bracket" on_select={select(2)}>JSON</:tab>
          <:tab icon="hero-beaker" on_select={select(3)}>{gettext("Test input")}</:tab>
          <:panel>
            <div class="basa-editor-pane overflow-hidden rounded-xl border border-zinc-200 bg-white dark:border-zinc-800">
              <div data-editor-root phx-update="ignore" id="rules-editor-root" class="h-full"></div>
            </div>
          </:panel>
          <:panel>
            <div class="basa-editor-pane basa-json-editor">
              <div data-json-root phx-update="ignore" id="rules-json-root" class="h-full"></div>
            </div>
          </:panel>
          <:panel>
            <div class="basa-editor-pane basa-json-editor">
              <div id="rules-context" phx-update="ignore" class="h-full"></div>
            </div>
          </:panel>
        </.tabs>
      </div>
    </Layouts.app>
    """
  end
end
