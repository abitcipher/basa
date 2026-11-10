defmodule BasaWeb.TransactionLive do
  use BasaWeb, :live_view

  require Ash.Query

  alias Basa.Witness
  alias Basa.Witness.{Act, Crypto, Evidence, Party, Store}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    user = socket.assigns.current_user

    case Witness.get_transaction(id, actor: user) do
      {:ok, _tx} ->
        if connected?(socket), do: Phoenix.PubSub.subscribe(Basa.PubSub, topic(id))

        {:ok,
         socket
         |> assign(
           page_title: gettext("Contract"),
           id: id,
           device: %{supported: nil, public_key: nil},
           mem_code: nil
         )
         |> allow_upload(:photos,
           accept: ~w(image/*),
           max_entries: 10,
           max_file_size: 15_000_000,
           auto_upload: true,
           progress: &handle_progress/3
         )
         |> allow_upload(:voice,
           accept: ~w(audio/*),
           max_entries: 1,
           max_file_size: 20_000_000,
           auto_upload: true,
           progress: &handle_progress/3
         )
         |> allow_upload(:files,
           accept: :any,
           max_entries: 5,
           max_file_size: 20_000_000,
           auto_upload: true,
           progress: &handle_progress/3
         )
         |> allow_upload(:act_photos,
           accept: ~w(image/*),
           max_entries: 10,
           max_file_size: 15_000_000,
           auto_upload: true,
           progress: &handle_progress/3
         )
         |> load()}

      {:error, _} ->
        {:ok,
         socket
         |> put_flash(:error, gettext("This contract is not available."))
         |> push_navigate(to: ~p"/bookings")}
    end
  end

  defp topic(id), do: "witness:#{id}"

  defp load(socket) do
    user = socket.assigns.current_user

    tx =
      Witness.get_transaction!(socket.assigns.id,
        actor: user,
        load: [booking: [lot: [:room]]]
      )

    parties =
      Party
      |> Ash.Query.filter(transaction_id == ^tx.id)
      |> Ash.Query.load(:user)
      |> Ash.read!(authorize?: false)

    evidence =
      Evidence
      |> Ash.Query.filter(transaction_id == ^tx.id and is_nil(act_id))
      |> Ash.Query.sort(position: :asc)
      |> Ash.read!(authorize?: false)

    mine = Enum.find(parties, &(&1.user_id == user.id))

    acts =
      Act
      |> Ash.Query.filter(transaction_id == ^tx.id)
      |> Ash.Query.load(:evidence)
      |> Ash.read!(authorize?: false)

    socket
    |> assign(
      tx: tx,
      parties: Map.new(parties, &{&1.role, &1}),
      mine: mine,
      evidence: evidence,
      acts: acts |> Enum.filter(& &1.sequence) |> Enum.sort_by(& &1.sequence),
      authority_requests:
        Basa.Witness.AuthorityRequest
        |> Ash.Query.filter(transaction_id == ^tx.id)
        |> Ash.Query.sort(decided_at: :asc)
        |> Ash.read!(actor: user),
      mem_received:
        Basa.Witness.MemAttestation
        |> Ash.Query.filter(transaction_id == ^tx.id and status == :received)
        |> Ash.read!(actor: user)
        |> MapSet.new(& &1.role),
      qes:
        Basa.Witness.QualifiedSignature
        |> Ash.Query.filter(transaction_id == ^tx.id and status == :signed)
        |> Ash.Query.sort(signed_at: :desc)
        |> Ash.read!(actor: user)
        |> Enum.reverse()
        |> Map.new(&{&1.role, &1}),
      qes_providers: Basa.Witness.QES.providers(),
      mem?: Basa.Services.on?(:mem),
      timestamp?: Basa.Witness.Timestamp.enabled?(),
      device_keys: device_keys(tx, mine, acts),
      my_draft:
        Enum.find(acts, &(&1.author_user_id == user.id and &1.status in [:draft, :unsigned]))
    )
    |> refresh_mem_code()
  end

  defp refresh_mem_code(%{assigns: %{mem_code: %{record: r}}} = socket) do
    case Ash.get(Basa.Witness.MemAttestation, r.id, authorize?: false) do
      {:ok, %{status: :pending} = fresh} ->
        assign(socket, mem_code: %{socket.assigns.mem_code | record: fresh})

      _ ->
        assign(socket, mem_code: nil)
    end
  end

  defp refresh_mem_code(socket), do: socket

  defp started(_record, {:ok, url}, _user), do: {:ok, url}

  defp started(record, {:ok, url, data}, user) do
    with {:ok, _} <- Witness.advance_qualified_signature(record, data, actor: user),
         do: {:ok, url}
  end

  defp started(_record, error, _user), do: error

  defp device_keys(%{storage_mode: :encrypted} = tx, %Party{role: role}, acts) do
    for {scope, act} <- [{tx.id, nil} | Enum.map(acts, &{&1.id, &1})],
        Basa.Witness.Store.sealed_share(tx, role, act) &&
          Basa.Witness.Store.key(tx, act: act) == {:error, :shares_missing},
        into: MapSet.new(),
        do: scope
  end

  defp device_keys(_tx, _mine, _acts), do: MapSet.new()

  defp changed(socket) do
    Phoenix.PubSub.broadcast(Basa.PubSub, topic(socket.assigns.id), :witness_changed)
    load(socket)
  end

  @impl true
  def handle_info(:witness_changed, socket), do: {:noreply, load(socket)}

  defp handle_progress(:act_photos, entry, socket) when entry.done? do
    %{tx: tx, current_user: user, my_draft: draft} = socket.assigns

    result =
      consume_uploaded_entry(socket, entry, fn %{path: path} ->
        {:ok,
         Store.add(tx, :photo, entry.client_type || "image/jpeg", File.read!(path), user,
           act: draft
         )}
      end)

    case result do
      {:ok, _} ->
        {:noreply, changed(socket)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("This file could not be added."))}
    end
  end

  defp handle_progress(name, entry, socket) when entry.done? do
    %{tx: tx, current_user: user} = socket.assigns
    kind = %{photos: :photo, voice: :voice, files: :other}[name]

    result =
      consume_uploaded_entry(socket, entry, fn %{path: path} ->
        {:ok,
         Store.add(
           tx,
           kind,
           entry.client_type || "application/octet-stream",
           File.read!(path),
           user
         )}
      end)

    case result do
      {:ok, _} ->
        {:noreply, changed(socket)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("This file could not be added."))}
    end
  end

  defp handle_progress(_name, _entry, socket), do: {:noreply, socket}

  @impl true
  def handle_event("validate", _params, socket), do: {:noreply, socket}

  def handle_event("legal_name", %{"legal_name" => name}, socket) do
    socket.assigns.mine
    |> Witness.set_legal_name(String.trim(name), actor: socket.assigns.current_user)
    |> done(socket)
  end

  def handle_event("terms", params, socket) do
    deposit =
      case Decimal.parse(String.trim(params["deposit"] || "")) do
        {d, ""} -> d
        _ -> nil
      end

    socket.assigns.tx
    |> Witness.update_terms(
      %{deposit_amount: deposit, claims_window_days: params["claims_window_days"]},
      actor: socket.assigns.current_user
    )
    |> done(socket)
  end

  def handle_event("consumer", params, socket) do
    socket.assigns.tx
    |> Witness.declare_consumer(params["consumer"] == "true", actor: socket.assigns.current_user)
    |> done(socket)
  end

  def handle_event("device:status", %{"supported" => supported, "public_key" => key}, socket) do
    {:noreply,
     assign(socket, device: %{supported: supported, public_key: key && Base.decode64!(key)})}
  end

  def handle_event("connect_device", _params, socket),
    do: {:noreply, push_event(socket, "device:connect", %{})}

  def handle_event("device:register", %{"public_key" => key, "box_key" => box}, socket) do
    key = Base.decode64!(key)

    socket.assigns.mine
    |> Witness.register_device(key, Base.decode64!(box), actor: socket.assigns.current_user)
    |> done(assign(socket, device: %{supported: true, public_key: key}))
  end

  def handle_event("open", %{"path" => path, "scope" => scope}, socket) do
    %{tx: tx, mine: mine} = socket.assigns
    act = if scope != tx.id, do: Enum.find(socket.assigns.acts, &(&1.id == scope))

    case (scope == tx.id or act) && Basa.Witness.Store.sealed_share(tx, mine.role, act) do
      sealed when is_binary(sealed) ->
        {:noreply,
         push_event(socket, "device:unwrap", %{
           sealed: Base.encode64(sealed),
           aad: scope,
           for: scope <> " " <> path
         })}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("device:share", %{"share" => nil}, socket),
    do:
      {:noreply,
       put_flash(
         socket,
         :error,
         gettext("This device cannot open the files. Use the device you connected.")
       )}

  def handle_event("device:share", %{"share" => share, "for" => target}, socket) do
    [scope, path] = String.split(target, " ", parts: 2)

    if String.starts_with?(path, "/transactions/#{socket.assigns.tx.id}/") do
      ticket =
        Basa.Witness.Openings.put(socket.assigns.current_user.id, scope, Base.decode64!(share))

      {:noreply, push_event(socket, "witness:download", %{url: path <> "?ticket=" <> ticket})}
    else
      {:noreply, socket}
    end
  end

  def handle_event("prepare", _params, socket) do
    socket.assigns.tx
    |> Witness.prepare_transaction(actor: socket.assigns.current_user)
    |> done(socket)
  end

  def handle_event("sign", _params, socket) do
    message = Crypto.seal_message(socket.assigns.tx.basa_hash)
    {:noreply, push_event(socket, "device:sign", %{message: Base.encode64(message)})}
  end

  def handle_event("device:signature", %{"signature" => nil}, socket),
    do:
      {:noreply,
       put_flash(
         socket,
         :error,
         gettext("This device has no signing key. Use the device you connected.")
       )}

  def handle_event(
        "device:signature",
        %{"signature" => signature, "for" => "counter:" <> id},
        socket
      ) do
    act = Ash.get!(Act, id, authorize?: false)

    act
    |> Witness.countersign_act(Base.decode64!(signature), actor: socket.assigns.current_user)
    |> done(socket)
  end

  def handle_event("device:signature", %{"signature" => signature, "for" => "act:" <> id}, socket) do
    act = Ash.get!(Act, id, authorize?: false)

    act
    |> Witness.sign_act(Base.decode64!(signature), actor: socket.assigns.current_user)
    |> done(socket)
  end

  def handle_event("device:signature", %{"signature" => signature}, socket) do
    socket.assigns.tx
    |> Witness.sign_transaction(Base.decode64!(signature), actor: socket.assigns.current_user)
    |> done(socket)
  end

  def handle_event("start_act", %{"kind" => kind}, socket)
      when kind in ~w(return acceptance claim settlement dispute) do
    socket.assigns.tx.id
    |> Witness.start_act(String.to_existing_atom(kind), %{terms: %{}},
      actor: socket.assigns.current_user
    )
    |> done(socket)
  end

  def handle_event("send_act", params, socket) do
    user = socket.assigns.current_user
    draft = socket.assigns.my_draft

    terms =
      (params["terms"] || %{})
      |> Map.take(~w(note amount deposit_kept))
      |> Map.new(fn {k, v} -> {k, String.trim(v)} end)
      |> Map.reject(fn {_k, v} -> v == "" end)

    fixed =
      case draft.status do
        :unsigned ->
          {:ok, draft}

        :draft ->
          with {:ok, d} <- Witness.edit_act(draft, terms, actor: user),
               do: Witness.fix_act(d, actor: user)
      end

    case fixed do
      {:ok, act} ->
        {:noreply,
         socket
         |> load()
         |> push_event("device:sign", %{
           message: Base.encode64(Crypto.act_message(act.hash)),
           for: "act:" <> act.id
         })}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, act_error(error))}
    end
  end

  def handle_event("countersign", %{"id" => id}, socket) do
    act = Enum.find(socket.assigns.acts, &(&1.id == id))
    message = Base.encode64(Crypto.act_message(act.hash))
    {:noreply, push_event(socket, "device:sign", %{message: message, for: "counter:" <> id})}
  end

  def handle_event("reject_act", %{"id" => id}, socket) do
    socket.assigns.acts
    |> Enum.find(&(&1.id == id))
    |> Witness.reject_act(actor: socket.assigns.current_user)
    |> done(socket)
  end

  def handle_event("mem:issue", _params, socket) do
    %{tx: tx, current_user: user} = socket.assigns

    case Witness.issue_mem_attestation(tx.id, actor: user) do
      {:ok, record} ->
        text = Basa.Witness.MemAttest.request_text(record, tx)
        {:ok, svg} = Basa.Witness.Native.qr_svg(text)

        {:noreply,
         assign(socket,
           mem_code: %{
             record: record,
             text: text,
             svg: svg,
             label: Basa.Witness.MemAttest.label(tx)
           }
         )}

      {:error, _} ->
        {:noreply,
         put_flash(socket, :error, gettext("This contract cannot be confirmed in person."))}
    end
  end

  def handle_event("mem:paste", %{"code" => text}, socket) do
    with %{record: record} <- socket.assigns.mem_code,
         {:ok, bytes} <- Basa.Witness.MemAttest.from_text(text),
         {:ok, _} <-
           Witness.receive_mem_attestation(record, bytes, :paste,
             actor: socket.assigns.current_user
           ) do
      {:noreply, socket |> assign(mem_code: nil) |> changed()}
    else
      _ ->
        {:noreply,
         put_flash(
           socket,
           :error,
           gettext("MEM's code was not accepted. Show a new code and confirm again.")
         )}
    end
  end

  def handle_event("qes:start", %{"provider" => name}, socket) do
    %{tx: tx, mine: mine, current_user: user} = socket.assigns
    provider_id = Enum.find(Basa.Witness.QES.providers(), &(to_string(&1) == name))

    with provider when is_atom(provider) and not is_nil(provider) <-
           Basa.Witness.QES.provider(provider_id),
         {:ok, record} <- Witness.start_qualified_signature(tx.id, provider_id, actor: user),
         {:ok, url} <-
           started(
             record,
             provider.start(record, tx, mine, Basa.Witness.QES.return_url(record)),
             user
           ) do
      {:noreply,
       if(String.starts_with?(url, "/"),
         do: redirect(socket, to: url),
         else: redirect(socket, external: url)
       )}
    else
      _ ->
        {:noreply,
         put_flash(socket, :error, gettext("Signing could not start. Try again later."))}
    end
  end

  def handle_event("cancel", _params, socket) do
    socket.assigns.tx
    |> Witness.cancel_transaction(actor: socket.assigns.current_user)
    |> done(socket)
  end

  def handle_event("cancel_upload", %{"ref" => ref, "name" => name}, socket),
    do: {:noreply, cancel_upload(socket, String.to_existing_atom(name), ref)}

  defp act_error(error) do
    text = Exception.message(error)

    cond do
      text =~ "photos" ->
        gettext("Add photos of the condition you return it in.")

      text =~ "few words" ->
        gettext("Describe it in a few words.")

      text =~ "kept part" or text =~ "deposit the lessor keeps" ->
        gettext("The kept part must be between 0 and the deposit.")

      text =~ "amount" ->
        gettext("The amount must be a positive number.")

      text =~ "window is over" ->
        gettext("The claims window is over.")

      true ->
        gettext("That didn't work. Please try again.")
    end
  end

  defp done({:ok, _}, socket), do: {:noreply, changed(socket)}

  defp done({:error, _}, socket),
    do: {:noreply, put_flash(socket, :error, gettext("That didn't work. Please try again."))}

  defp checklist(assigns) do
    [
      {gettext("Both parties gave their legal names"),
       Enum.all?(Map.values(assigns.parties), &(&1.legal_name not in [nil, ""]))},
      {gettext("Both parties connected the device they sign on"),
       Enum.all?(Map.values(assigns.parties), &(&1.public_key != nil))},
      {gettext("At least one photo of the condition"),
       Enum.any?(assigns.evidence, &(&1.kind == :photo))}
    ]
  end

  defp available(%{tx: tx, mine: mine, acts: acts}) do
    open_settlement? =
      Enum.any?(acts, &(&1.kind == :settlement and &1.status == :awaiting_counter))

    for kind <- [:return, :delivery, :acceptance, :claim, :settlement, :dispute],
        Basa.Witness.Acts.allowed?(tx, kind, mine.role) == :ok,
        not (kind == :settlement and open_settlement?),
        do: kind
  end

  defp act_label(:return, _), do: gettext("Return")
  defp act_label(:delivery, _), do: gettext("Delivery confirmed")
  defp act_label(:acceptance, :sale), do: gettext("All is fine")
  defp act_label(:acceptance, _), do: gettext("Return accepted")
  defp act_label(:claim, _), do: gettext("Claim")
  defp act_label(:settlement, _), do: gettext("Settlement")
  defp act_label(:dispute, _), do: gettext("Dispute")
  defp act_label(:auto_acceptance, :sale), do: gettext("Delivery accepted automatically")
  defp act_label(:auto_acceptance, _), do: gettext("Return accepted automatically")

  defp start_label(:return, _), do: gettext("Return it")
  defp start_label(:delivery, _), do: gettext("Confirm delivery")
  defp start_label(:acceptance, :sale), do: gettext("All is fine")
  defp start_label(:acceptance, _), do: gettext("Accept the return")
  defp start_label(:claim, _), do: gettext("Raise a claim")
  defp start_label(:settlement, _), do: gettext("Propose a settlement")
  defp start_label(:dispute, _), do: gettext("Declare a dispute")

  defp author_label(:basa, _), do: "BASA"
  defp author_label(role, type), do: role_label(role, type)

  defp deposit_label(%{deposit_status: :held}), do: gettext("held")
  defp deposit_label(%{deposit_status: :released}), do: gettext("returned to the lessee")
  defp deposit_label(%{deposit_status: :kept}), do: gettext("kept by the lessor")

  defp deposit_label(%{deposit_status: :partly_kept} = tx),
    do:
      gettext("%{kept} kept by the lessor, the rest returned",
        kept: Basa.Money.format(tx.deposit_kept, tx.booking.currency)
      )

  defp deposit_label(_), do: ""

  defp role_label(:offeror, :sale), do: gettext("Seller")
  defp role_label(:acceptor, :sale), do: gettext("Buyer")
  defp role_label(:offeror, _), do: gettext("Lessor")
  defp role_label(:acceptor, _), do: gettext("Lessee")

  defp kind_label(:contract), do: gettext("Contract")
  defp kind_label(:photo), do: gettext("Photo")
  defp kind_label(:voice), do: gettext("Voice recording")
  defp kind_label(:other), do: gettext("File")

  defp kind_icon(:contract), do: "hero-document-text"
  defp kind_icon(:photo), do: "hero-photo"
  defp kind_icon(:voice), do: "hero-microphone"
  defp kind_icon(:other), do: "hero-paper-clip"

  defp number(tx), do: tx.id |> String.slice(0, 8) |> String.upcase()

  defp local(nil, _tz), do: ""
  defp local(dt, tz), do: dt |> DateTime.shift_zone!(tz) |> Calendar.strftime("%d.%m.%Y %H:%M")

  defp size(bytes) when bytes < 1_000_000, do: "#{max(div(bytes, 1000), 1)} KB"
  defp size(bytes), do: "#{Float.round(bytes / 1_000_000, 1)} MB"

  defp this_device?(device, %Party{public_key: key}), do: key != nil and device.public_key == key

  @impl true
  def render(assigns) do
    assigns =
      assign(assigns,
        after_sealing: [:sealed, :returned, :claimed, :settled, :closed, :disputed],
        available: available(assigns),
        my_draft_files:
          if(assigns.my_draft, do: Basa.Witness.Acts.files(assigns.my_draft.id), else: []),
        tz: assigns.tx.booking.lot.timezone,
        other: Enum.find(Map.values(assigns.parties), &(&1.id != assigns.mine.id)),
        checklist: checklist(assigns)
      )

    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} unread={@unread_count}>
      <.back_button navigate={~p"/bookings"} label={gettext("Bookings")} class="mb-1.5" />

      <div class="mb-4 flex flex-wrap items-start justify-between gap-2">
        <div>
          <h1 class="flex items-center gap-1.5 text-xl font-bold">
            {gettext("Contract No. %{number}", number: number(@tx))}
            <.help_link topic="contract-and-return" />
          </h1>
          <p class="text-sm opacity-70">
            {@tx.booking.lot.title} · {local(@tx.booking.starts_at, @tz)} – {local(
              @tx.booking.ends_at,
              @tz
            )}
          </p>
        </div>
        <.state_badge state={@tx.status} />
      </div>

      <div id="device-key" phx-hook="DeviceKey" data-user-id={@current_user.id}></div>

      <.card
        :if={@authority_requests != []}
        id="authority-access"
        padding="medium"
        rounded="large"
        class="mb-4 text-sm"
      >
        <h2 class="mb-1 flex items-center gap-2 font-semibold">
          <.icon name="hero-building-library" class="size-5" /> {gettext("Access by an authority")}
          <.info_tip id="authority-access-info">
            {gettext(
              "An authority asked for this contract's evidence, under the procedure in the contract. Two BASA admins approved the request; the files are opened only offline, with the recovery key."
            )}
          </.info_tip>
        </h2>
        <ul class="grid gap-1">
          <li :for={r <- @authority_requests}>
            <b>{r.authority}</b>, {gettext("reference")} {r.reference} · {gettext(
              "approved on %{date}",
              date: Calendar.strftime(r.decided_at, "%d.%m.%Y")
            )}
            <span :if={r.opened_at}>
              · {gettext("handed over on %{date}", date: Calendar.strftime(r.opened_at, "%d.%m.%Y"))}
            </span>
          </li>
        </ul>
      </.card>

      <.card padding="medium" rounded="large" class="mb-4">
        <h2 class="mb-2 font-semibold">{gettext("Parties")}</h2>
        <div class="divide-y divide-zinc-200 dark:divide-zinc-800">
          <div
            :for={role <- [:offeror, :acceptor]}
            id={"party-#{role}"}
            class="flex flex-wrap items-center gap-x-3 gap-y-1 py-2 text-sm"
          >
            <span class="w-24 opacity-60">{role_label(role, @tx.contract_type)}</span>
            <span class="flex-1 font-medium">
              {@parties[role].legal_name || @parties[role].user.display_name}
              <span :if={!@parties[role].legal_name} class="font-normal opacity-60">
                · {gettext("legal name not given yet")}
              </span>
            </span>
            <span
              :if={@parties[role].public_key && !@parties[role].signature}
              class="text-xs opacity-70"
            >
              <.icon name="hero-device-phone-mobile" class="size-4" /> {gettext("device connected")}
            </span>
            <span
              :if={@parties[role].signature}
              class="text-xs font-medium text-success-light dark:text-success-dark"
            >
              <.icon name="hero-check-badge" class="size-4" /> {gettext("signed")}
            </span>
          </div>
        </div>
      </.card>

      <div :if={@tx.status == :draft} class="space-y-4">
        <.card padding="medium" rounded="large">
          <h2 class="mb-2 flex items-center gap-1.5 font-semibold">
            {gettext("Your legal name")}
            <.info_tip id="legal-name-info">
              {gettext("As on your identity document. It goes into the contract.")}
            </.info_tip>
          </h2>
          <form id="legal-name-form" phx-submit="legal_name" class="flex flex-wrap items-end gap-2">
            <div class="min-w-56 flex-1">
              <.text_field
                name="legal_name"
                id="legal-name"
                value={@mine.legal_name}
                size="medium"
                required
              />
            </div>
            <.button type="submit" color="primary" variant="default">{gettext("Save")}</.button>
          </form>
        </.card>

        <.card padding="medium" rounded="large">
          <h2 class="mb-2 font-semibold">{gettext("Terms")}</h2>
          <form
            :if={@mine.role == :offeror}
            id="terms-form"
            phx-submit="terms"
            class="flex flex-wrap items-end gap-3"
          >
            <div :if={@tx.contract_type != :sale} class="w-40">
              <.text_field
                name="deposit"
                id="deposit"
                label={gettext("Deposit (%{currency})", currency: @tx.booking.currency)}
                value={@tx.deposit_amount && Decimal.to_string(@tx.deposit_amount)}
                inputmode="decimal"
                size="medium"
              />
            </div>
            <div class="w-40">
              <.number_field
                name="claims_window_days"
                id="claims-window"
                label={gettext("Days for claims")}
                value={@tx.claims_window_days}
                min="1"
                max="60"
                size="medium"
              />
            </div>
            <.button type="submit" color="primary" variant="bordered">{gettext("Save")}</.button>
          </form>
          <p :if={@mine.role == :acceptor} class="text-sm">
            <span :if={@tx.contract_type != :sale}>
              {gettext("Deposit")}:
              <b>{Basa.Money.format(@tx.deposit_amount, @tx.booking.currency)}</b>
              ·
            </span>
            {gettext("Days for claims")}: <b>{@tx.claims_window_days}</b>
          </p>
          <form :if={@mine.role == :acceptor} id="consumer-form" phx-change="consumer" class="mt-3">
            <input type="hidden" name="consumer" value="false" />
            <label class="flex cursor-pointer items-center gap-2 text-sm">
              <input
                type="checkbox"
                name="consumer"
                value="true"
                checked={@tx.consumer}
                class="size-4 rounded"
              />
              {if @tx.contract_type == :sale,
                do: gettext("I buy as a private person (consumer)"),
                else: gettext("I rent as a private person (consumer)")}
            </label>
          </form>
          <p :if={@mine.role == :offeror} class="mt-2 text-sm opacity-70">
            {if @tx.consumer,
              do: gettext("The other party acts as a private person (consumer)."),
              else: gettext("The other party has not said they act as a private person.")}
          </p>
        </.card>

        <.card padding="medium" rounded="large">
          <h2 class="mb-3 flex items-center gap-1.5 font-semibold">
            {gettext("Evidence")}
            <.info_tip id="evidence-info">
              {gettext(
                "Photos of the condition, a voice reading by each of you, and any other files you both agree on."
              )}
            </.info_tip>
          </h2>
          <.evidence_list evidence={@evidence} tx={@tx} device_keys={@device_keys} />

          <div class="mt-3 flex flex-wrap gap-2">
            <form id="photos-upload" phx-change="validate" phx-submit="validate">
              <label class="inline-flex cursor-pointer items-center gap-1.5 rounded-lg border border-zinc-300 px-3 py-1.5 text-sm hover:bg-zinc-50 dark:border-zinc-700 dark:hover:bg-zinc-800">
                <.icon name="hero-camera" class="size-4" /> {gettext("Add photos")}
                <.live_file_input upload={@uploads.photos} class="hidden" />
              </label>
            </form>
            <form id="files-upload" phx-change="validate" phx-submit="validate">
              <label class="inline-flex cursor-pointer items-center gap-1.5 rounded-lg border border-zinc-300 px-3 py-1.5 text-sm hover:bg-zinc-50 dark:border-zinc-700 dark:hover:bg-zinc-800">
                <.icon name="hero-paper-clip" class="size-4" /> {gettext("Add a file")}
                <.live_file_input upload={@uploads.files} class="hidden" />
              </label>
            </form>
          </div>

          <div
            :for={
              entry <- @uploads.photos.entries ++ @uploads.files.entries ++ @uploads.voice.entries
            }
            class="mt-2 flex items-center gap-2 text-xs"
          >
            <span class="truncate">{entry.client_name}</span>
            <.progress value={entry.progress} size="small" color="primary" class="w-24" />
          </div>

          <div class="mt-4 rounded-xl bg-zinc-50 p-3 dark:bg-zinc-900">
            <p class="mb-2 text-sm">
              {gettext("Voice reading: record yourself reading this text aloud.")}
            </p>
            <blockquote class="mb-3 border-l-4 border-primary-light pl-3 text-sm italic dark:border-primary-dark">
              {gettext("I, %{name}, confirm contract No. %{number} for “%{offer}”, %{date}.",
                name: @mine.legal_name || @mine.user.display_name,
                number: number(@tx),
                offer: @tx.booking.lot.title,
                date: local(@tx.booking.starts_at, @tz)
              )}
            </blockquote>
            <form id="voice-upload" phx-change="validate" phx-submit="validate">
              <.live_file_input upload={@uploads.voice} class="hidden" />
            </form>
            <div
              id="voice-recorder"
              phx-hook="VoiceRecorder"
              data-upload="voice"
              data-state="idle"
              class="group flex items-center gap-3"
            >
              <button
                type="button"
                data-voice-toggle
                class="inline-flex cursor-pointer items-center gap-1.5 rounded-full bg-primary-light px-4 py-1.5 text-sm text-white hover:bg-primary-hover-light dark:bg-primary-dark dark:text-zinc-950"
              >
                <.icon name="hero-microphone" class="size-4" />
                <span class="group-data-[state=recording]:hidden">{gettext("Record")}</span>
                <span class="hidden group-data-[state=recording]:inline">{gettext("Stop and add")}</span>
              </button>
              <span
                data-voice-timer
                class="hidden font-mono text-sm group-data-[state=recording]:inline"
              >0:00</span>
              <span class="hidden text-sm text-danger-light group-data-[state=denied]:inline">
                {gettext("Allow the microphone in your browser to record.")}
              </span>
            </div>
          </div>
        </.card>

        <.card padding="medium" rounded="large">
          <h2 class="mb-1 font-semibold">{gettext("Your signing device")}</h2>
          <%= cond do %>
            <% @device.supported == false -> %>
              <p class="text-sm text-danger-light dark:text-danger-dark">
                {gettext(
                  "This browser cannot make a signing key. Use a current Chrome, Firefox, Safari or the Telegram app."
                )}
              </p>
            <% this_device?(@device, @mine) -> %>
              <p class="text-sm">
                <.icon name="hero-check-circle" class="size-4 text-success-light" />
                {gettext("This device is connected. You will sign the contract on it.")}
              </p>
            <% true -> %>
              <p class="mb-2 text-sm opacity-70">
                {if @mine.public_key,
                  do:
                    gettext(
                      "You connected another device. Connect this one instead if you want to sign here."
                    ),
                  else:
                    gettext(
                      "Connect the device you will sign on. Its key never leaves it; BASA only gets the public part."
                    )}
              </p>
              <.button
                id="connect-device"
                phx-click="connect_device"
                color="primary"
                variant="bordered"
                size="small"
              >
                {gettext("Connect this device")}
              </.button>
          <% end %>
        </.card>

        <.card padding="medium" rounded="large">
          <ul class="mb-3 space-y-1 text-sm">
            <li :for={{label, done?} <- @checklist} class="flex items-center gap-2">
              <.icon
                name={if done?, do: "hero-check-circle-solid", else: "hero-minus-circle"}
                class={[
                  "size-4",
                  if(done?, do: "text-success-light dark:text-success-dark", else: "opacity-40")
                ]}
              />
              {label}
            </li>
          </ul>
          <.button
            id="prepare"
            phx-click="prepare"
            color="primary"
            variant="default"
            disabled={not Enum.all?(@checklist, &elem(&1, 1))}
            data-confirm={
              gettext("The evidence and terms will be frozen and the contract made. Continue?")
            }
          >
            {gettext("Prepare for signing")}
          </.button>
        </.card>
      </div>

      <div :if={@tx.status == :signing} class="space-y-4">
        <.card padding="medium" rounded="large">
          <h2 class="mb-3 flex items-center gap-1.5 font-semibold">
            {gettext("Read and sign")}
            <.info_tip id="sign-info">
              {gettext(
                "Both of you sign the same BASA-HASH: it covers the contract and every evidence file."
              )}
            </.info_tip>
          </h2>
          <.evidence_list evidence={@evidence} tx={@tx} device_keys={@device_keys} />
          <.hash_box tx={@tx} />
          <div class="mt-4">
            <%= cond do %>
              <% @mine.signature -> %>
                <p class="text-sm">{gettext("You signed. Waiting for the other party.")}</p>
              <% this_device?(@device, @mine) -> %>
                <.button id="sign" phx-click="sign" color="primary" variant="default">
                  {gettext("Sign on this device")}
                </.button>
              <% true -> %>
                <p class="text-sm text-warning-light dark:text-warning-dark">
                  {gettext("Open this page on the device you connected to sign.")}
                </p>
            <% end %>
          </div>
        </.card>
      </div>

      <div :if={@tx.status in @after_sealing} class="space-y-4">
        <.card padding="medium" rounded="large">
          <h2 class="mb-1 flex items-center gap-1.5 font-semibold">
            {gettext("Sealed")}
            <.info_tip id="sealed-info">
              <span class="block">
                {gettext("Keep the BASA-HASH: it finds this contract and proves it unchanged.")}
              </span>
              <span class="mt-1 block">
                {gettext("Anyone can check a shared file at")}
                <.link navigate={~p"/verify"} class="underline">{url(~p"/verify")}</.link>
              </span>
            </.info_tip>
          </h2>
          <p class="mb-3 text-sm opacity-70">
            {gettext("Signed by both parties on %{date}.", date: local(@tx.sealed_at, @tz))}
          </p>
          <.hash_box tx={@tx} />
          <p class="mt-3 text-sm">
            <%= if @tx.timestamped_at do %>
              <.icon name="hero-clock" class="size-4" />
              {gettext("Independent time: %{time} (timestamp authority).",
                time: local(@tx.timestamped_at, @tz)
              )}
            <% else %>
              <span :if={@timestamp?} class="opacity-70">
                {gettext("The independent timestamp is being requested…")}
              </span>
              <span :if={!@timestamp?} id="timestamp-off" class="opacity-70">
                {gettext(
                  "No independent timestamp yet: the timestamp service is switched off. Your signatures hold without it; it is added when the service is back."
                )}
              </span>
            <% end %>
          </p>
          <div class="mt-4">
            <.evidence_list evidence={@evidence} tx={@tx} device_keys={@device_keys} share />
          </div>
        </.card>

        <.mem_confirm
          :if={@mem? or @tx.mem_confirmed_at}
          tx={@tx}
          mine={@mine}
          received={@mem_received}
          code={@mem_code}
          tz={@tz}
        />

        <.qualified
          tx={@tx}
          mine={@mine}
          signed={@qes}
          providers={@qes_providers}
          tz={@tz}
        />

        <.card id="after-handover" padding="medium" rounded="large">
          <h2 class="mb-1 font-semibold">{gettext("After the handover")}</h2>
          <p :if={@tx.deposit_amount} class="text-sm">
            {gettext("Deposit")}: <b>{Basa.Money.format(@tx.deposit_amount, @tx.booking.currency)}</b>
            <span :if={deposit_label(@tx) != ""}>· {deposit_label(@tx)}</span>
          </p>
          <p :if={@tx.status == :returned and @tx.claims_until} class="text-sm opacity-80">
            {gettext(
              "The lessor can raise a claim until %{date}; after that the return counts as accepted.",
              date: local(@tx.claims_until, @tz)
            )}
          </p>
          <p :if={@tx.status == :delivered and @tx.claims_until} class="text-sm opacity-80">
            {gettext(
              "The buyer can raise a claim for hidden defects until %{date}; after that the delivery counts as accepted.",
              date: local(@tx.claims_until, @tz)
            )}
          </p>

          <ol :if={@acts != []} id="acts" class="mt-3 space-y-2">
            <li
              :for={a <- @acts}
              id={"act-#{a.sequence}"}
              class="rounded-xl border border-zinc-200 p-3 text-sm dark:border-zinc-800"
            >
              <div class="flex flex-wrap items-center gap-2">
                <b>{act_label(a.kind, @tx.contract_type)}</b>
                <span class="opacity-60">· {author_label(a.author, @tx.contract_type)} · {local(
                  a.effective_at || a.updated_at,
                  @tz
                )}</span>
                <span
                  :if={a.status == :awaiting_counter}
                  class="text-warning-light dark:text-warning-dark"
                >
                  · {gettext("waiting for the other side")}
                </span>
                <span :if={a.status == :rejected} class="opacity-60">· {gettext("not accepted")}</span>
              </div>
              <p :if={a.terms["note"]} class="mt-1">{a.terms["note"]}</p>
              <p :if={a.terms["amount"]} class="mt-1">
                {gettext("Claimed")}: {Basa.Money.format(
                  Decimal.new(a.terms["amount"]),
                  @tx.booking.currency
                )}
              </p>
              <p :if={a.terms["deposit_kept"]} class="mt-1">
                {gettext("Kept from the deposit")}: {Basa.Money.format(
                  Decimal.new(a.terms["deposit_kept"]),
                  @tx.booking.currency
                )}
              </p>
              <div :if={a.evidence != []} class="mt-1 flex flex-wrap gap-x-3 text-xs">
                <.file_link
                  :for={e <- a.evidence}
                  path={~p"/transactions/#{@tx.id}/acts/#{a.id}/files/#{e.position}"}
                  scope={a.id}
                  device_keys={@device_keys}
                  class="hover:underline"
                >
                  <.icon name="hero-photo" class="size-3.5" /> {gettext("Photo")} {e.position + 1}
                </.file_link>
              </div>
              <div
                :if={a.status == :awaiting_counter and a.author_user_id != @current_user.id}
                class="mt-2 flex flex-wrap gap-2"
              >
                <.button
                  :if={this_device?(@device, @mine)}
                  id={"countersign-#{a.sequence}"}
                  phx-click="countersign"
                  phx-value-id={a.id}
                  color="primary"
                  size="small"
                >
                  {gettext("Agree and sign")}
                </.button>
                <.button phx-click="reject_act" phx-value-id={a.id} variant="bordered" size="small">
                  {gettext("Do not agree")}
                </.button>
              </div>
            </li>
          </ol>

          <form
            :if={@my_draft}
            id="act-form"
            phx-submit="send_act"
            phx-change="validate"
            class="mt-4 space-y-3 rounded-xl bg-zinc-50 p-3 dark:bg-zinc-900"
          >
            <p class="font-medium">{act_label(@my_draft.kind, @tx.contract_type)}</p>
            <.textarea_field
              :if={@my_draft.kind in [:return, :delivery, :claim, :settlement, :dispute]}
              id="act-note"
              name="terms[note]"
              value={@my_draft.terms["note"]}
              label={gettext("In a few words")}
              rows="2"
            />
            <.text_field
              :if={@my_draft.kind == :claim}
              id="act-amount"
              name="terms[amount]"
              value={@my_draft.terms["amount"]}
              label={gettext("Amount claimed (%{currency})", currency: @tx.booking.currency)}
              inputmode="decimal"
            />
            <.text_field
              :if={@my_draft.kind == :settlement}
              id="act-kept"
              name="terms[deposit_kept]"
              value={@my_draft.terms["deposit_kept"]}
              label={gettext("Kept from the deposit (%{currency})", currency: @tx.booking.currency)}
              inputmode="decimal"
            />
            <div :if={@my_draft.kind in [:return, :delivery, :claim]}>
              <p class="mb-1 text-sm">
                {case @my_draft.kind do
                  :return -> gettext("Photos of the condition you return it in")
                  :delivery -> gettext("Photos of what you received")
                  _ -> gettext("Photos of what is wrong")
                end}
              </p>
              <div class="flex flex-wrap items-center gap-2 text-xs">
                <span :for={e <- @my_draft_files} class="rounded bg-white px-2 py-1 dark:bg-zinc-800">
                  <.icon name="hero-photo" class="size-3.5" /> {gettext("Photo")} {e.position + 1}
                </span>
                <label
                  :if={@my_draft.status == :draft}
                  class="inline-flex cursor-pointer items-center gap-1.5 rounded-lg border border-zinc-300 px-3 py-1.5 text-sm dark:border-zinc-700"
                >
                  <.icon name="hero-camera" class="size-4" /> {gettext("Add photos")}
                  <.live_file_input upload={@uploads.act_photos} class="hidden" />
                </label>
              </div>
            </div>
            <%= if this_device?(@device, @mine) do %>
              <.button id="send-act" type="submit" color="primary">{gettext("Sign and send")}</.button>
            <% else %>
              <p class="text-sm text-warning-light dark:text-warning-dark">
                {gettext("Open this page on the device you connected to sign.")}
              </p>
            <% end %>
          </form>

          <div :if={!@my_draft and @available != []} class="mt-4 flex flex-wrap gap-2">
            <.button
              :for={kind <- @available}
              id={"start-#{kind}"}
              phx-click="start_act"
              phx-value-kind={kind}
              color={if kind == :dispute, do: "danger", else: "primary"}
              variant={if kind in [:return, :delivery, :acceptance], do: "default", else: "bordered"}
              size="small"
            >
              {start_label(kind, @tx.contract_type)}
            </.button>
          </div>
        </.card>
      </div>

      <p :if={@tx.status == :cancelled} class="text-sm opacity-70">
        {gettext("This contract was cancelled.")}
      </p>

      <div :if={@tx.status in [:draft, :signing]} class="mt-6">
        <.button
          id="cancel-contract"
          phx-click="cancel"
          variant="transparent"
          color="danger"
          size="small"
          data-confirm={gettext("Cancel this contract?")}
        >
          {gettext("Cancel the contract")}
        </.button>
      </div>
    </Layouts.app>
    """
  end

  attr :path, :string, required: true
  attr :scope, :string, required: true
  attr :device_keys, :any, required: true
  attr :download, :boolean, default: false
  attr :class, :any, default: nil
  attr :rest, :global
  slot :inner_block, required: true

  defp file_link(assigns) do
    ~H"""
    <button
      :if={MapSet.member?(@device_keys, @scope)}
      type="button"
      phx-click="open"
      phx-value-path={@path}
      phx-value-scope={@scope}
      class={["cursor-pointer text-left", @class]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </button>
    <a
      :if={!MapSet.member?(@device_keys, @scope)}
      href={@path}
      target={!@download && "_blank"}
      class={@class}
      {@rest}
    >
      {render_slot(@inner_block)}
    </a>
    """
  end

  attr :evidence, :list, required: true
  attr :tx, :map, required: true
  attr :share, :boolean, default: false
  attr :device_keys, :any, default: MapSet.new()

  defp evidence_list(assigns) do
    ~H"""
    <ul id="evidence" class="divide-y divide-zinc-200 text-sm dark:divide-zinc-800">
      <li :if={@evidence == []} class="py-2 opacity-60">{gettext("No files yet.")}</li>
      <li :for={e <- @evidence} id={"evidence-#{e.position}"} class="flex items-center gap-2 py-2">
        <.icon name={kind_icon(e.kind)} class="size-4 opacity-70" />
        <.file_link
          path={~p"/transactions/#{@tx.id}/evidence/#{e.position}"}
          scope={@tx.id}
          device_keys={@device_keys}
          class="flex-1 truncate hover:underline"
        >
          {kind_label(e.kind)} {e.position + 1}
        </.file_link>
        <span class="text-xs opacity-60">{size(e.size)}</span>
        <.file_link
          :if={@share}
          path={~p"/transactions/#{@tx.id}/disclose/#{e.position}"}
          scope={@tx.id}
          device_keys={@device_keys}
          download
          class="inline-flex items-center gap-1 text-xs text-primary-light hover:underline dark:text-primary-dark"
          title={
            gettext(
              "Download this file with the proof that it belongs to the contract, to give to someone else"
            )
          }
        >
          <.icon name="hero-share" class="size-3.5" /> {gettext("Share with proof")}
        </.file_link>
      </li>
    </ul>
    """
  end

  attr :tx, :map, required: true
  attr :mine, :map, default: nil
  attr :signed, :map, required: true
  attr :providers, :list, required: true
  attr :tz, :string, required: true

  defp qualified(assigns) do
    ~H"""
    <.card :if={@providers != [] or @signed != %{}} id="qes" padding="medium" rounded="large">
      <h2 class="mb-1 flex items-center gap-2 font-semibold">
        <.icon name="hero-finger-print" class="size-5" /> {gettext("Qualified electronic signature")}
      </h2>
      <p
        :if={@tx.qes_signed_at}
        id="qes-done"
        class="mb-2 text-sm font-medium text-success-light dark:text-success-dark"
      >
        <.icon name="hero-check-badge" class="size-4" />
        {gettext("Both parties signed with a qualified signature (%{date}).",
          date: local(@tx.qes_signed_at, @tz)
        )}
      </p>
      <p
        :if={!@tx.qes_signed_at && qes_waiting(@signed) == :test}
        id="qes-test-only"
        class="mb-2 text-sm"
      >
        <.icon name="hero-beaker" class="size-4" />
        {gettext(
          "Both parties signed, but with test signatures: the contract reaches this level only with qualified signatures."
        )}
      </p>
      <p
        :if={!@tx.qes_signed_at && qes_waiting(@signed) == :not_qualified}
        id="qes-not-qualified"
        class="mb-2 text-sm"
      >
        <.icon name="hero-minus-circle" class="size-4" />
        {gettext(
          "Both parties signed, but the EU check did not confirm both signatures as qualified: the contract reaches this level only with qualified signatures."
        )}
      </p>
      <p
        :if={!@tx.qes_signed_at && qes_waiting(@signed) == :unchecked}
        id="qes-checking"
        class="mb-2 text-sm"
      >
        <.icon name="hero-clock" class="size-4" />
        {gettext("Both parties signed; the EU check of the signatures is not finished yet.")}
      </p>
      <p
        :if={!@tx.qes_signed_at && !(@signed[:offeror] && @signed[:acceptor])}
        class="mb-2 text-sm opacity-70"
      >
        {gettext(
          "Optional: each of you also signs the contract with Дія.Підпис or an EU qualified signature. It has the legal force of a handwritten signature."
        )}
      </p>
      <ul class="mb-3 grid gap-1 text-sm">
        <li :for={role <- [:offeror, :acceptor]} id={"qes-#{role}"}>
          <span class="inline-block w-24 opacity-60">{role_label(role, @tx.contract_type)}</span>
          <%= if s = @signed[role] do %>
            <span class="text-success-light dark:text-success-dark">
              <.icon name="hero-check" class="size-4" /> {s.subject}
            </span>
            <span class="text-xs opacity-60">· {s.issuer}</span>
            <span
              :if={s.test}
              class="ml-1 inline-block rounded bg-warning-light/20 px-1.5 text-xs dark:bg-warning-dark/20"
            >
              {gettext("test signature, not qualified")}
            </span>
            <span
              :if={!s.test && s.qualification == :qualified}
              id={"qes-#{role}-qualified"}
              class="ml-1 inline-block rounded bg-success-light/20 px-1.5 text-xs dark:bg-success-dark/20"
            >
              {gettext("qualified, confirmed by the EU check")}
            </span>
            <span
              :if={s.qualification == :not_qualified}
              id={"qes-#{role}-not-qualified"}
              class="ml-1 inline-block rounded bg-warning-light/20 px-1.5 text-xs dark:bg-warning-dark/20"
            >
              {gettext("not a qualified signature (EU check: %{result})",
                result:
                  Enum.join(
                    Enum.reject([s.qualification_indication, s.qualification_level], &is_nil/1),
                    ", "
                  )
              )}
            </span>
            <span :if={!s.test && s.qualification == :unchecked} class="ml-1 text-xs opacity-60">
              {gettext("EU check not finished yet")}
            </span>
            <span
              :if={s.name_matches == false}
              class="ml-1 text-xs text-danger-light dark:text-danger-dark"
            >
              {gettext("the name on the certificate differs from the legal name in the contract")}
            </span>
          <% else %>
            <span class="opacity-60">{gettext("not yet")}</span>
          <% end %>
        </li>
      </ul>
      <div :if={@mine && !@signed[@mine.role]} class="flex flex-wrap gap-2">
        <.button
          :for={p <- @providers}
          id={"qes-start-#{p}"}
          phx-click="qes:start"
          phx-value-provider={p}
          color="primary"
          variant="bordered"
        >
          {provider_label(p)}
        </.button>
      </div>
    </.card>
    """
  end

  defp qes_waiting(%{offeror: o, acceptor: a}) do
    cond do
      o.test or a.test -> :test
      :not_qualified in [o.qualification, a.qualification] -> :not_qualified
      :unchecked in [o.qualification, a.qualification] -> :unchecked
      true -> nil
    end
  end

  defp qes_waiting(_), do: nil

  defp provider_label(:dev), do: gettext("Sign with the test certification authority")
  defp provider_label(:csc), do: gettext("Sign with an EU qualified signature (eIDAS)")
  defp provider_label(other), do: to_string(other)

  attr :tx, :map, required: true
  attr :mine, :map, default: nil
  attr :received, :any, required: true
  attr :code, :map, default: nil
  attr :tz, :string, required: true

  defp mem_confirm(assigns) do
    ~H"""
    <.card id="mem-confirm" padding="medium" rounded="large">
      <h2 class="mb-1 flex items-center gap-2 font-semibold">
        <.icon name="hero-hand-raised" class="size-5" /> {gettext("Confirm in person in MEM")}
        <.info_tip :if={!@tx.mem_confirmed_at} id="mem-info">
          {gettext(
            "Optional, when you meet: each of you opens “Confirm in person” in MEM, scans your own code from this page, then you scan each other's phones. It records that you both confirmed this contract face to face."
          )}
        </.info_tip>
      </h2>
      <%= if @tx.mem_confirmed_at do %>
        <p id="mem-confirmed" class="text-sm font-medium text-success-light dark:text-success-dark">
          <.icon name="hero-check-badge" class="size-4" />
          {gettext("Confirmed in person in MEM on %{date}: both phones swapped fresh codes.",
            date: local(@tx.mem_confirmed_at, @tz)
          )}
        </p>
      <% else %>
        <ul class="mb-3 grid gap-1 text-sm">
          <li :for={role <- [:offeror, :acceptor]} id={"mem-#{role}"}>
            <span class="inline-block w-24 opacity-60">{role_label(role, @tx.contract_type)}</span>
            <%= if MapSet.member?(@received, role) do %>
              <span class="text-success-light dark:text-success-dark">
                <.icon name="hero-check" class="size-4" /> {gettext("confirmed")}
              </span>
            <% else %>
              <span class="opacity-60">{gettext("not yet")}</span>
            <% end %>
          </li>
        </ul>
        <%= if @mine && !MapSet.member?(@received, @mine.role) do %>
          <%= if @code do %>
            <div id="mem-code" class="flex flex-wrap items-start gap-4">
              <div class="w-60 shrink-0 rounded-lg bg-white p-2 [&_svg]:h-auto [&_svg]:w-full">
                {Phoenix.HTML.raw(@code.svg)}
              </div>
              <div class="min-w-56 flex-1 space-y-2 text-sm">
                <p>
                  {gettext("Scan this in MEM. MEM shows what you confirm: %{label}…",
                    label: @code.label
                  )}
                </p>
                <p class="opacity-70">{gettext("The code works once, for 15 minutes.")}</p>
                <.clipboard text={@code.text} id="copy-mem-code">
                  <:trigger>
                    <span class="cursor-pointer underline">{gettext("Copy the code instead")}</span>
                  </:trigger>
                </.clipboard>
                <form id="mem-paste-form" phx-submit="mem:paste" class="space-y-2">
                  <.text_field
                    name="code"
                    id="mem-paste"
                    value=""
                    size="small"
                    placeholder={gettext("If MEM could not send it: paste MEM's code here")}
                  />
                  <.button type="submit" color="natural" variant="bordered" size="small">
                    {gettext("Add")}
                  </.button>
                </form>
              </div>
            </div>
          <% else %>
            <.button id="mem-issue" phx-click="mem:issue" color="primary" variant="bordered">
              {gettext("Show my MEM code")}
            </.button>
          <% end %>
        <% end %>
      <% end %>
    </.card>
    """
  end

  attr :tx, :map, required: true

  defp hash_box(assigns) do
    ~H"""
    <div class="mt-3 rounded-xl border border-primary-light/40 bg-primary-bordered-bg-light p-3 dark:border-primary-dark/40 dark:bg-primary-bordered-bg-dark">
      <p class="mb-1 text-xs font-semibold tracking-wide uppercase opacity-70">BASA-HASH</p>
      <div class="flex items-start gap-2">
        <code id="basa-hash" class="flex-1 font-mono text-sm break-all">{Crypto.to_text(@tx.basa_hash)}</code>
        <.clipboard text={Crypto.to_text(@tx.basa_hash)} id="copy-hash">
          <:trigger>
            <span class="cursor-pointer" title={gettext("Copy")}>
              <.icon name="hero-clipboard-document" class="size-4" />
            </span>
          </:trigger>
        </.clipboard>
      </div>
    </div>
    """
  end
end
