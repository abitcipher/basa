defmodule BasaWeb.Admin.ImportLive do
  use BasaWeb, :live_view

  alias Basa.Import

  @impl true
  def mount(_params, _session, socket) do
    if socket.assigns.current_user.role == :admin do
      agreement = Import.current_agreement()

      {:ok,
       socket
       |> assign(page_title: gettext("Import from web pages"), email: "")
       |> assign(agreement: agreement, draft: (agreement && agreement.body) || default_text())
       |> load()}
    else
      {:ok, socket |> put_flash(:error, gettext("Admins only.")) |> push_navigate(to: ~p"/")}
    end
  end

  defp load(socket) do
    {:ok, access} = Import.list_access(actor: socket.assigns.current_user)
    assign(socket, access: access)
  end

  @impl true
  def handle_event("grant", %{"email" => email}, socket) do
    case Import.grant_by_email(email, actor: socket.assigns.current_user) do
      {:ok, _} ->
        {:noreply,
         socket |> assign(email: "") |> put_flash(:info, gettext("Access granted.")) |> load()}

      {:error, :no_user} ->
        {:noreply,
         socket |> assign(email: email) |> put_flash(:error, gettext("No user with this email."))}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, Enum.join(BasaWeb.ErrorText.messages(error), "; "))}
    end
  end

  def handle_event("revoke", %{"id" => id}, socket) do
    access = Enum.find(socket.assigns.access, &(&1.id == id))
    {:ok, _} = Import.revoke_access(access, actor: socket.assigns.current_user)
    {:noreply, socket |> put_flash(:info, gettext("Access revoked.")) |> load()}
  end

  def handle_event("publish", %{"body" => body}, socket) do
    case Import.publish_agreement(body, actor: socket.assigns.current_user) do
      {:ok, agreement} ->
        {:noreply,
         socket
         |> assign(agreement: agreement, draft: agreement.body)
         |> put_flash(:info, gettext("Agreement version %{v} published.", v: agreement.version))}

      {:error, error} ->
        {:noreply,
         socket
         |> assign(draft: body)
         |> put_flash(:error, Enum.join(BasaWeb.ErrorText.messages(error), "; "))}
    end
  end

  defp default_text do
    gettext("""
    By using the import tool you confirm that you have the right to use the content you import (texts, prices, photos) and that you take full responsibility for how it is used on BASA. BASA reads the pages you point it to on your behalf; imported listings are drafts until you review and publish them.
    """)
  end

  defp status(%{revoked_at: %DateTime{}}), do: gettext("Revoked")
  defp status(%{accepted_version: nil}), do: gettext("Agreement not confirmed yet")

  defp status(%{accepted_version: v}),
    do: gettext("Agreement version %{v} confirmed", v: v)

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} unread={@unread_count} wide>
      <.page_title title={gettext("Import from web pages")} info_id="admin-import-info">
        <:info>
          {gettext(
            "Only users you grant access can import listings from web pages, and only after they confirm the current user agreement. Publishing a new version asks everyone to confirm again."
          )}
        </:info>
      </.page_title>

      <div class="grid gap-6 lg:grid-cols-2">
        <section>
          <h2 class="mb-2 font-semibold">{gettext("Access")}</h2>
          <form id="grant-form" phx-submit="grant" class="mb-4 flex items-end gap-2">
            <div class="flex-1">
              <.email_field
                id="grant-email"
                name="email"
                value={@email}
                label={gettext("User's email")}
                size="medium"
              />
            </div>
            <.button type="submit" color="primary" variant="default">{gettext("Grant")}</.button>
          </form>

          <.empty_state :if={@access == []} title={gettext("No one has access yet.")} />
          <div class="space-y-2">
            <.card :for={a <- @access} id={"access-#{a.id}"} padding="small" rounded="large">
              <div class="flex flex-wrap items-center justify-between gap-2">
                <div class="min-w-0">
                  <p class="truncate font-medium">{a.email}</p>
                  <p class="text-xs opacity-60">{status(a)}</p>
                </div>
                <.button
                  :if={is_nil(a.revoked_at)}
                  size="small"
                  variant="bordered"
                  phx-click="revoke"
                  phx-value-id={a.id}
                  data-confirm={gettext("Revoke access for %{email}?", email: a.email)}
                >
                  {gettext("Revoke")}
                </.button>
              </div>
            </.card>
          </div>
        </section>

        <section>
          <h2 class="mb-2 font-semibold">
            {gettext("User agreement")}
            <span :if={@agreement} class="text-sm font-normal opacity-60">
              {gettext("version %{v}", v: @agreement.version)}
            </span>
            <span :if={is_nil(@agreement)} id="agreement-none" class="text-sm font-normal opacity-60">
              {gettext("not published yet")}
            </span>
          </h2>
          <form id="agreement-form" phx-submit="publish" class="space-y-2">
            <.textarea_field
              id="agreement-body"
              name="body"
              value={@draft}
              rows="12"
              label={gettext("Text")}
            />
            <.button type="submit" color="primary" variant="default">{gettext("Publish new version")}</.button>
          </form>
        </section>
      </div>
    </Layouts.app>
    """
  end
end
