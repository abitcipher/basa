defmodule BasaWeb.Dev.QesLive do
  use BasaWeb, :live_view

  require Ash.Query

  alias Basa.Witness.{Crypto, Party, QES, QualifiedSignature}
  alias Basa.Witness.QES.DevProvider

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    user = socket.assigns.current_user

    with {:ok, state} <- QES.state_from_token(token),
         %QualifiedSignature{user_id: id} = record when id == user.id <- pending(state) do
      tx = Ash.get!(Basa.Witness.Transaction, record.transaction_id, authorize?: false)

      party =
        Party
        |> Ash.Query.filter(transaction_id == ^tx.id and role == ^record.role)
        |> Ash.read_one!(authorize?: false)

      {:ok,
       assign(socket,
         page_title: gettext("Test certification authority"),
         record: record,
         tx: tx,
         name: party.legal_name || user.display_name || to_string(user.email)
       )}
    else
      _ ->
        {:ok,
         socket
         |> put_flash(:error, gettext("This signing session is not valid any more."))
         |> push_navigate(to: ~p"/bookings")}
    end
  end

  @impl true
  def handle_event("sign", _params, socket) do
    %{record: record, tx: tx, name: name} = socket.assigns
    {:ok, cms} = DevProvider.sign(record.user_id, name, tx.basa_hash)
    {:noreply, redirect(socket, external: DevProvider.return_with(record, cms))}
  end

  def handle_event("cancel", _params, socket) do
    url = QES.return_url(socket.assigns.record) <> "?error=cancelled"
    {:noreply, redirect(socket, external: url)}
  end

  defp pending(state) do
    QualifiedSignature
    |> Ash.Query.filter(state == ^state and status == :pending)
    |> Ash.read_one!(authorize?: false)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} unread={@unread_count}>
      <.card id="dev-qes" padding="large" rounded="large" class="mx-auto max-w-lg">
        <p class="mb-1 text-xs font-semibold tracking-wide uppercase opacity-60">
          {gettext("Development only")}
        </p>
        <h1 class="mb-2 text-lg font-bold">{gettext("Test certification authority")}</h1>
        <p class="mb-4 text-sm opacity-70">
          {gettext(
            "This page stands in for Дія.Підпис or an eIDAS provider. It makes a test signature: it checks the whole flow, but it is not a qualified signature and has no legal effect."
          )}
        </p>
        <dl class="mb-4 grid grid-cols-[8rem_1fr] gap-y-1 text-sm">
          <dt class="opacity-60">{gettext("Certificate for")}</dt>
          <dd id="dev-qes-name" class="font-medium">{@name}</dd>
          <dt class="opacity-60">{gettext("Document")}</dt>
          <dd class="font-mono text-xs break-all">{Crypto.to_text(@tx.basa_hash)}</dd>
        </dl>
        <div class="flex justify-end gap-2">
          <.button id="dev-qes-cancel" phx-click="cancel" color="natural" variant="bordered">
            {gettext("Cancel")}
          </.button>
          <.button id="dev-qes-sign" phx-click="sign" color="primary">
            {gettext("Sign (test)")}
          </.button>
        </div>
      </.card>
    </Layouts.app>
    """
  end
end
