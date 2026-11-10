defmodule BasaWeb.Admin.PhotosLive do
  use BasaWeb, :live_view

  alias Basa.Moderation

  @impl true
  def mount(_params, _session, socket) do
    if socket.assigns.current_user.role == :admin do
      {:ok, socket |> assign(page_title: gettext("Photo checks")) |> load()}
    else
      {:ok, socket |> put_flash(:error, gettext("Admins only.")) |> push_navigate(to: ~p"/")}
    end
  end

  defp load(socket) do
    checks = Moderation.list_to_review!(actor: socket.assigns.current_user, load: [:owner])
    assign(socket, checks: checks)
  end

  @impl true
  def handle_event("review", %{"id" => id, "decision" => decision}, socket)
      when decision in ["kept", "removed"] do
    actor = socket.assigns.current_user

    with %{} = check <- Enum.find(socket.assigns.checks, &(&1.id == id)),
         {:ok, _} <-
           Moderation.review_photo(check, String.to_existing_atom(decision), actor: actor) do
      message =
        if decision == "kept",
          do: gettext("Kept: renters see the photo."),
          else: gettext("Removed: renters don't see the photo.")

      {:noreply, socket |> put_flash(:info, message) |> load()}
    else
      _ -> {:noreply, put_flash(socket, :error, gettext("That didn't work. Please try again."))}
    end
  end

  defp place("items/" <> _), do: gettext("Item photo")
  defp place("rooms/" <> _), do: gettext("Room photo")
  defp place("entrance/" <> _), do: gettext("The way in")
  defp place("street/" <> _), do: gettext("Street view")
  defp place("stock/" <> _), do: gettext("Kept picture")
  defp place(_), do: gettext("Photo")

  defp percent(nil), do: "–"
  defp percent(p), do: "#{round(p * 100)}%"

  defp top_clip(scores) do
    (scores["clip"] || %{})
    |> Enum.reject(fn {k, _} -> k in ~w(gear room place people text) end)
    |> Enum.sort_by(fn {_, p} -> -p end)
    |> Enum.take(3)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} unread={@unread_count}>
      <.page_title title={gettext("Photo checks")} info_id="photos-check-info" help="admin">
        <:info>
          {gettext(
            "Photos the checks hid or sent here. Keep one and renters see it again; remove it and they don't. Your decision stays when photos are checked again."
          )}
        </:info>
      </.page_title>

      <p :if={@checks == []} id="photo-checks-empty" class="opacity-70">
        {gettext("Nothing to review.")}
      </p>

      <div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
        <.card
          :for={c <- @checks}
          id={"photo-check-#{c.id}"}
          padding="small"
          rounded="large"
          class="flex flex-col gap-2"
        >
          <a href={Basa.Storage.url(c.key)} target="_blank" class="block overflow-hidden rounded-lg">
            <img
              src={Basa.Storage.url(c.key)}
              alt=""
              class="aspect-[4/3] w-full object-cover"
              loading="lazy"
            />
          </a>
          <div class="flex flex-wrap items-center gap-2 text-xs">
            <.badge :if={c.verdict == :block} size="extra_small" rounded="full" color="danger">
              {gettext("Hidden")}
            </.badge>
            <.badge :if={c.verdict == :flag} size="extra_small" rounded="full" color="warning">
              {gettext("To check")}
            </.badge>
            <span class="opacity-80">{place(c.key)}</span>
            <span :if={c.owner} class="opacity-80">· {BasaWeb.Layouts.display_name(c.owner)}</span>
          </div>
          <ul class="list-inside list-disc text-sm">
            <li :for={r <- c.reasons}>{Moderation.reason_text(r)}</li>
          </ul>
          <p class="text-xs opacity-70">
            {gettext("Nudity %{p}", p: percent(c.scores["nsfw"]))}<span :for={
              {k, p} <- top_clip(c.scores)
            }> · {k} {percent(p)}</span>
            · {gettext("level %{level}", level: c.level)}
          </p>
          <div class="mt-auto flex gap-2">
            <.button
              id={"keep-#{c.id}"}
              size="small"
              variant="default"
              color="primary"
              phx-click="review"
              phx-value-id={c.id}
              phx-value-decision="kept"
            >
              {gettext("Keep")}
            </.button>
            <.button
              id={"remove-#{c.id}"}
              size="small"
              variant="bordered"
              color="natural"
              phx-click="review"
              phx-value-id={c.id}
              phx-value-decision="removed"
              data-confirm={gettext("Remove this photo for renters?")}
            >
              {gettext("Remove")}
            </.button>
          </div>
        </.card>
      </div>
    </Layouts.app>
    """
  end
end
