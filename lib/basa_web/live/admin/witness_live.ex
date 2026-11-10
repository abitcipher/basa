defmodule BasaWeb.Admin.WitnessLive do
  use BasaWeb, :live_view

  require Ash.Query

  alias Basa.Witness
  alias Basa.Witness.{AccessLog, Act, AuthorityRequest, Crypto, Transaction, Verify}

  @impl true
  def mount(_params, _session, socket) do
    if socket.assigns.current_user.role == :admin do
      {:ok, assign(socket, page_title: gettext("Contracts"), result: nil)}
    else
      {:ok, socket |> put_flash(:error, gettext("Admins only.")) |> push_navigate(to: ~p"/")}
    end
  end

  @impl true
  def handle_params(%{"id" => id}, _uri, socket) do
    tx =
      Ash.get!(Transaction, id,
        actor: socket.assigns.current_user,
        load: [booking: :lot]
      )

    if connected?(socket) and socket.assigns[:selected] == nil,
      do: Phoenix.PubSub.subscribe(Basa.PubSub, "witness:#{tx.id}")

    {:noreply, socket |> assign(selected: tx, result: nil) |> load_detail()}
  end

  def handle_params(_params, _uri, socket),
    do: {:noreply, socket |> assign(selected: nil) |> load_list()}

  defp load_list(socket) do
    admin = socket.assigns.current_user

    txs =
      Transaction
      |> Ash.Query.sort(inserted_at: :desc)
      |> Ash.Query.load(booking: :lot)
      |> Ash.read!(actor: admin)

    last =
      AccessLog
      |> Ash.Query.filter(action == :verify)
      |> Ash.Query.sort(inserted_at: :desc)
      |> Ash.read!(actor: admin)
      |> Enum.uniq_by(& &1.transaction_id)
      |> Map.new(&{&1.transaction_id, &1})

    acts =
      Act
      |> Ash.Query.filter(not is_nil(sequence))
      |> Ash.read!(authorize?: false)
      |> Enum.frequencies_by(& &1.transaction_id)

    assign(socket, transactions: txs, last_checks: last, act_counts: acts)
  end

  defp load_detail(socket) do
    tx = socket.assigns.selected

    logs =
      AccessLog
      |> Ash.Query.filter(transaction_id == ^tx.id)
      |> Ash.Query.sort(inserted_at: :desc)
      |> Ash.Query.load(:actor)
      |> Ash.read!(actor: socket.assigns.current_user)

    requests =
      AuthorityRequest
      |> Ash.Query.filter(transaction_id == ^tx.id)
      |> Ash.Query.sort(inserted_at: :desc)
      |> Ash.Query.load([:filed_by, :decided_by])
      |> Ash.read!(actor: socket.assigns.current_user)

    assign(socket, logs: logs, requests: requests)
  end

  defp request!(socket, id),
    do: Ash.get!(AuthorityRequest, id, actor: socket.assigns.current_user)

  defp step(result, socket, ok_text) do
    case result do
      {:ok, _} ->
        {:noreply, socket |> load_detail() |> put_flash(:info, ok_text)}

      {:error, error} ->
        message =
          error
          |> Ash.Error.to_error_class()
          |> Map.get(:errors, [])
          |> Enum.map_join("; ", &Exception.message/1)

        {:noreply, put_flash(socket, :error, message)}
    end
  end

  @impl true
  def handle_info(:witness_changed, %{assigns: %{selected: %{}}} = socket),
    do: {:noreply, load_detail(socket)}

  def handle_info(_message, socket), do: {:noreply, socket}

  @impl true
  def handle_event("check", %{"id" => id}, socket) do
    tx = Ash.get!(Transaction, id, actor: socket.assigns.current_user)
    result = Verify.transaction(tx, actor: socket.assigns.current_user, reason: "admin check")

    socket = if socket.assigns.selected, do: load_detail(socket), else: load_list(socket)
    {:noreply, assign(socket, result: result)}
  end

  def handle_event("file_request", params, socket) do
    attrs = %{
      authority: params["authority"],
      basis: params["basis"],
      reference: params["reference"],
      received_on: params["received_on"] != "" && params["received_on"],
      notes: params["notes"],
      notify_parties: params["withhold"] != "true",
      no_notice_reason: params["no_notice_reason"]
    }

    socket.assigns.selected.id
    |> Witness.file_authority_request(attrs, actor: socket.assigns.current_user)
    |> step(socket, gettext("Request filed. A second admin decides on it."))
  end

  def handle_event("approve_request", %{"id" => id}, socket) do
    socket
    |> request!(id)
    |> Witness.approve_authority_request(actor: socket.assigns.current_user)
    |> step(socket, gettext("Request approved."))
  end

  def handle_event("reject_request", %{"request_id" => id, "note" => note}, socket) do
    socket
    |> request!(id)
    |> Witness.reject_authority_request(note, actor: socket.assigns.current_user)
    |> step(socket, gettext("Request rejected."))
  end

  def handle_event("notify_request", %{"id" => id}, socket) do
    socket
    |> request!(id)
    |> Witness.notify_authority_request(actor: socket.assigns.current_user)
    |> step(socket, gettext("The parties are told."))
  end

  def handle_event("record_opening", %{"request_id" => id} = params, socket) do
    case Base.decode16(String.trim(params["report_sha256"] || ""), case: :mixed) do
      {:ok, sha} ->
        socket
        |> request!(id)
        |> Witness.record_opening(
          %{
            key_holders: params["key_holders"],
            handed_over_to: params["handed_over_to"],
            report_sha256: sha
          },
          actor: socket.assigns.current_user
        )
        |> step(socket, gettext("Opening recorded."))

      :error ->
        {:noreply,
         put_flash(socket, :error, gettext("The report hash is 64 hexadecimal characters."))}
    end
  end

  def handle_event("check_all", _params, socket) do
    results = Verify.all(actor: socket.assigns.current_user, reason: "admin check")
    failed = Enum.count(results, fn {_, r} -> not r.ok? end)

    {:noreply,
     socket
     |> load_list()
     |> put_flash(
       if(failed == 0, do: :info, else: :error),
       gettext("Checked %{count}, failed %{failed}.", count: length(results), failed: failed)
     )}
  end

  defp number(tx), do: tx.id |> String.slice(0, 8) |> String.upcase()

  defp when_text(nil), do: "—"
  defp when_text(dt), do: Calendar.strftime(dt, "%d.%m.%Y %H:%M")

  defp check_name({:file, n}), do: gettext("File %{n}", n: n + 1)
  defp check_name({:act, n}), do: gettext("Act %{n}", n: n)
  defp check_name({:signature, role}), do: gettext("Signature: %{role}", role: role)
  defp check_name(:keys), do: gettext("Keys")
  defp check_name(:positions), do: gettext("File order")
  defp check_name(:manifest), do: gettext("Manifest")
  defp check_name(:basa_hash), do: "BASA-HASH"
  defp check_name(:timestamp), do: gettext("Timestamp")
  defp check_name(:in_person), do: gettext("Confirmed in person in MEM")
  defp check_name({:qualified, role}), do: gettext("Qualified signature: %{role}", role: role)
  defp check_name(other), do: inspect(other)

  defp action_label(:verify), do: gettext("Check")
  defp action_label(:open), do: gettext("Opened")
  defp action_label(:recovery), do: gettext("Recovery")
  defp action_label(:request), do: gettext("Authority request")

  defp basis_label(:court_order), do: gettext("Court order")
  defp basis_label(:lawful_request), do: gettext("Other lawful request")
  defp basis_label(:parties_cannot_act), do: gettext("The parties cannot act")

  defp request_status(:pending), do: gettext("waiting for a second admin")
  defp request_status(:approved), do: gettext("approved")
  defp request_status(:rejected), do: gettext("rejected")
  defp request_status(:opened), do: gettext("opened and handed over")

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} unread={@unread_count} wide>
      <%= if @selected do %>
        <div class="mb-4 flex flex-wrap items-center gap-2">
          <.back_button patch={~p"/admin/witness"} label={gettext("Contracts")} />
          <h1 class="text-xl font-bold">
            {gettext("Contract No. %{number}", number: number(@selected))}
          </h1>
          <.state_badge state={@selected.status} />
        </div>
        <p class="mb-3 text-sm opacity-70">
          {@selected.booking.lot.title} · {gettext("mode")}: {@selected.storage_mode}
          <span :if={@selected.basa_hash}> · <code class="text-xs">{Crypto.to_text(
            @selected.basa_hash
          )}</code></span>
        </p>

        <.button
          id="check-one"
          phx-click="check"
          phx-value-id={@selected.id}
          color="primary"
          size="small"
          icon="hero-shield-check"
        >
          {gettext("Check now")}
        </.button>

        <.card :if={@result} id="check-result" padding="medium" rounded="large" class="mt-4">
          <p class={[
            "mb-2 font-semibold",
            if(@result.ok?,
              do: "text-success-light dark:text-success-dark",
              else: "text-danger-light dark:text-danger-dark"
            )
          ]}>
            {if @result.ok?, do: gettext("Everything checks out."), else: gettext("Problems found.")}
          </p>
          <ul class="grid gap-1 text-sm sm:grid-cols-2">
            <li :for={{name, r} <- @result.checks} class="flex items-center gap-2">
              <.icon
                name={
                  case r do
                    :ok -> "hero-check-circle-solid"
                    :pending -> "hero-clock"
                    :test -> "hero-beaker"
                    :not_qualified -> "hero-minus-circle"
                    _ -> "hero-x-circle-solid"
                  end
                }
                class={[
                  "size-4",
                  r == :ok && "text-success-light dark:text-success-dark",
                  r in [:pending, :test, :not_qualified] && "opacity-50",
                  match?({:error, _}, r) && "text-danger-light dark:text-danger-dark"
                ]}
              />
              {check_name(name)}
              <span :if={match?({:error, _}, r)} class="text-xs opacity-70">{inspect(elem(r, 1))}</span>
              <span :if={r == :test} class="text-xs opacity-70">
                {gettext("test signature, not qualified")}
              </span>
              <span :if={r == :not_qualified} class="text-xs opacity-70">
                {gettext("not qualified (EU DSS)")}
              </span>
              <span :if={r == :pending and match?({:qualified, _}, name)} class="text-xs opacity-70">
                {gettext("waiting for the EU DSS check")}
              </span>
            </li>
          </ul>
        </.card>

        <.authority_requests
          :if={@selected.basa_hash}
          requests={@requests}
          tx={@selected}
          me={@current_user}
        />

        <h2 class="mt-6 mb-2 font-semibold">{gettext("Access log")}</h2>
        <div class="overflow-x-auto">
          <table id="access-log" class="w-full text-sm">
            <tr :for={l <- @logs} class="border-b border-zinc-200 dark:border-zinc-800">
              <td class="py-2 pr-3 whitespace-nowrap">{when_text(l.inserted_at)}</td>
              <td class="py-2 pr-3">{action_label(l.action)}</td>
              <td class="py-2 pr-3">{(l.actor && l.actor.display_name) || gettext("system")}</td>
              <td class="py-2 pr-3 opacity-70">{l.reason}</td>
              <td class={["py-2", l.result != "ok" && "text-danger-light dark:text-danger-dark"]}>
                {l.result}
              </td>
            </tr>
          </table>
          <p :if={@logs == []} class="text-sm opacity-60">{gettext("Nothing yet.")}</p>
        </div>
      <% else %>
        <div class="mb-4 flex flex-wrap items-center justify-between gap-2">
          <h1 class="flex items-center gap-1.5 text-xl font-bold">
            {gettext("Contracts")}
            <.info_tip id="contracts-info">
              {gettext(
                "Checks keys, files, manifest, signatures, timestamp and the acts after sealing. Evidence itself stays closed to admins."
              )}
            </.info_tip>
          </h1>
          <.button
            id="check-all"
            phx-click="check_all"
            color="primary"
            size="small"
            icon="hero-shield-check"
          >
            {gettext("Check all")}
          </.button>
        </div>
        <div class="overflow-x-auto">
          <table id="contracts" class="w-full text-sm">
            <thead>
              <tr class="border-b border-zinc-200 text-left text-xs opacity-60 dark:border-zinc-800">
                <th class="py-2 pr-3 font-medium">{gettext("No.")}</th>
                <th class="py-2 pr-3 font-medium">{gettext("Offer")}</th>
                <th class="py-2 pr-3 font-medium">{gettext("Status")}</th>
                <th class="py-2 pr-3 font-medium">{gettext("Sealed")}</th>
                <th class="py-2 pr-3 font-medium">{gettext("Acts")}</th>
                <th class="py-2 font-medium">{gettext("Last check")}</th>
              </tr>
            </thead>
            <tr
              :for={tx <- @transactions}
              id={"contract-#{tx.id}"}
              class="border-b border-zinc-200 dark:border-zinc-800"
            >
              <td class="py-2 pr-3">
                <.link patch={~p"/admin/witness/#{tx.id}"} class="font-mono hover:underline">{number(
                  tx
                )}</.link>
              </td>
              <td class="py-2 pr-3">{tx.booking.lot.title}</td>
              <td class="py-2 pr-3"><.state_badge state={tx.status} /></td>
              <td class="py-2 pr-3 whitespace-nowrap">{when_text(tx.sealed_at)}</td>
              <td class="py-2 pr-3">{Map.get(@act_counts, tx.id, 0)}</td>
              <td class="py-2">
                <%= case @last_checks[tx.id] do %>
                  <% nil -> %>
                    <span class="opacity-50">—</span>
                  <% log -> %>
                    <span class={
                      if log.result == "ok",
                        do: "text-success-light dark:text-success-dark",
                        else: "text-danger-light dark:text-danger-dark"
                    }>
                      {if log.result == "ok", do: gettext("ok"), else: gettext("failed")}
                    </span>
                    <span class="text-xs opacity-60">{when_text(log.inserted_at)}</span>
                <% end %>
              </td>
            </tr>
          </table>
          <p :if={@transactions == []} class="text-sm opacity-60">{gettext("No contracts yet.")}</p>
        </div>
      <% end %>
    </Layouts.app>
    """
  end

  attr :requests, :list, required: true
  attr :tx, :map, required: true
  attr :me, :map, required: true

  defp authority_requests(assigns) do
    ~H"""
    <section id="authority-requests" class="mt-6">
      <h2 class="mb-3 flex items-center gap-1.5 font-semibold">
        {gettext("Authority requests")}
        <.info_tip id="authority-requests-info">
          {gettext(
            "A court order or another lawful request, or no party can act any more. A second admin decides; the parties are told unless the law forbids it; the recovery key holders open the kit offline."
          )}
        </.info_tip>
      </h2>

      <.card
        :for={r <- @requests}
        id={"request-#{r.id}"}
        padding="medium"
        rounded="large"
        class="mb-3 text-sm"
      >
        <div class="flex flex-wrap items-baseline justify-between gap-2">
          <p class="font-semibold">{r.authority} · {r.reference}</p>
          <span class="text-xs opacity-70">{request_status(r.status)}</span>
        </div>
        <p class="opacity-70">
          {basis_label(r.basis)}
          <span :if={r.received_on}> · {gettext("received")} {Calendar.strftime(
            r.received_on,
            "%d.%m.%Y"
          )}</span>
          · {gettext("filed by")} {r.filed_by && r.filed_by.display_name}
          <span :if={r.decided_by}> · {gettext("decided by")} {r.decided_by.display_name}</span>
        </p>
        <p :if={r.notes} class="mt-1">{r.notes}</p>
        <p :if={r.decision_note} class="mt-1">{gettext("Reason")}: {r.decision_note}</p>
        <p :if={r.status in [:approved, :opened]} class="mt-1">
          <%= if r.parties_notified_at do %>
            {gettext("Parties told on %{date}.", date: when_text(r.parties_notified_at))}
          <% else %>
            {gettext("Notice withheld")}: {r.no_notice_reason}
          <% end %>
        </p>
        <p :if={r.status == :opened} class="mt-1">
          {gettext("Opened by %{holders}; handed over to %{to}.",
            holders: r.key_holders,
            to: r.handed_over_to
          )}
          <code class="block truncate text-xs opacity-60">{Base.encode16(r.report_sha256,
            case: :lower
          )}</code>
        </p>

        <div :if={r.status == :pending and r.filed_by_id != @me.id} class="mt-3 flex flex-wrap gap-2">
          <.button
            id={"approve-#{r.id}"}
            phx-click="approve_request"
            phx-value-id={r.id}
            color="primary"
            size="small"
            data-confirm={gettext("Approve access for this authority?")}
          >
            {gettext("Approve")}
          </.button>
          <form id={"reject-#{r.id}"} phx-submit="reject_request" class="flex flex-wrap gap-2">
            <input type="hidden" name="request_id" value={r.id} />
            <.text_field
              name="note"
              id={"reject-note-#{r.id}"}
              placeholder={gettext("Why it is rejected")}
              size="small"
              required
            />
            <.button type="submit" size="small" variant="bordered">{gettext("Reject")}</.button>
          </form>
        </div>
        <p :if={r.status == :pending and r.filed_by_id == @me.id} class="mt-2 text-xs opacity-70">
          {gettext("Another admin has to decide on a request you filed.")}
        </p>

        <div :if={r.status in [:approved, :opened]} class="mt-3 flex flex-wrap gap-2">
          <.button_link
            href={~p"/admin/witness/requests/#{r.id}/kit"}
            size="small"
            variant="bordered"
            icon="hero-arrow-down-tray"
          >
            {gettext("Recovery kit")}
          </.button_link>
          <.button
            :if={is_nil(r.parties_notified_at)}
            phx-click="notify_request"
            phx-value-id={r.id}
            size="small"
            variant="bordered"
            data-confirm={gettext("Tell the parties now? Only when the law allows it.")}
          >
            {gettext("Tell the parties")}
          </.button>
        </div>

        <form
          :if={r.status == :approved}
          id={"opening-#{r.id}"}
          phx-submit="record_opening"
          class="mt-3 grid gap-2 sm:grid-cols-3"
        >
          <input type="hidden" name="request_id" value={r.id} />
          <.text_field
            name="key_holders"
            id={"holders-#{r.id}"}
            label={gettext("Opened by (key holders)")}
            size="small"
            required
          />
          <.text_field
            name="handed_over_to"
            id={"handed-#{r.id}"}
            label={gettext("Handed over to")}
            size="small"
            required
          />
          <.text_field
            name="report_sha256"
            id={"report-#{r.id}"}
            label={gettext("Report SHA-256")}
            size="small"
            required
          />
          <div class="sm:col-span-3">
            <.button type="submit" size="small" color="primary">{gettext("Record the opening")}</.button>
          </div>
        </form>
      </.card>

      <details id="new-request" class="rounded-lg border border-zinc-200 p-3 dark:border-zinc-800">
        <summary class="cursor-pointer text-sm font-medium">{gettext("File a request")}</summary>
        <form id="request-form" phx-submit="file_request" class="mt-3 grid gap-3 sm:grid-cols-2">
          <.text_field
            name="authority"
            id="request-authority"
            label={gettext("Who asks (court, body)")}
            size="small"
            required
          />
          <.native_select id="request-basis" name="basis" label={gettext("Basis")} size="small">
            <:option value="court_order">{gettext("Court order")}</:option>
            <:option value="lawful_request">{gettext("Other lawful request")}</:option>
            <:option value="parties_cannot_act">{gettext("The parties cannot act")}</:option>
          </.native_select>
          <.text_field
            name="reference"
            id="request-reference"
            label={gettext("Their reference (case, order No.)")}
            size="small"
            required
          />
          <.date_time_field
            name="received_on"
            id="request-received"
            type="date"
            label={gettext("Received on")}
            size="small"
          />
          <div class="sm:col-span-2">
            <.textarea_field name="notes" id="request-notes" label={gettext("Notes")} size="small" />
          </div>
          <label class="flex cursor-pointer items-center gap-2 text-sm sm:col-span-2">
            <input type="checkbox" name="withhold" value="true" class="size-4 rounded" />
            {gettext("The law forbids telling the parties for now")}
          </label>
          <div class="sm:col-span-2">
            <.text_field
              name="no_notice_reason"
              id="request-no-notice"
              label={gettext("Why the parties may not be told (legal ground)")}
              size="small"
            />
          </div>
          <div class="sm:col-span-2">
            <.button type="submit" color="primary" size="small">{gettext("File the request")}</.button>
          </div>
        </form>
      </details>
    </section>
    """
  end
end
