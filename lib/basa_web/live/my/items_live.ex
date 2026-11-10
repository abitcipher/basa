defmodule BasaWeb.My.ItemsLive do
  use BasaWeb, :live_view

  alias Basa.{Catalog, JsonSchema, Storage}
  alias BasaWeb.PhotoUploads

  @max_photos 6

  @impl true
  def mount(_params, _session, socket) do
    categories =
      Catalog.list_categories!(authorize?: false)
      |> Enum.filter(&(&1.kind == :equipment))
      |> Enum.sort_by(& &1.position)

    {:ok,
     socket
     |> assign(
       page_title: gettext("My items"),
       max_photos: @max_photos,
       photo_notice: nil,
       categories: categories,
       ai?: Basa.AI.enabled?(),
       pictures?: Basa.Images.configured?()
     )
     |> allow_upload(:photos,
       accept: ~w(.jpg .jpeg .png .webp),
       max_entries: @max_photos,
       max_file_size: 12_000_000,
       auto_upload: true,
       progress: &handle_progress/3
     )
     |> load_items()}
  end

  @impl true
  def handle_params(params, _uri, socket),
    do: {:noreply, apply_action(socket, socket.assigns.live_action, params)}

  defp apply_action(socket, :index, _), do: assign(socket, form: nil, preview: nil)

  defp apply_action(socket, :show, %{"id" => id}) do
    actor = socket.assigns.current_user
    item = id |> Catalog.get_item!(actor: actor) |> Ash.load!(:category, actor: actor)

    assign(socket,
      form: nil,
      preview: item,
      preview_credits: item.photos |> Basa.Images.credits() |> Map.values()
    )
  end

  defp apply_action(socket, :new, _) do
    form =
      AshPhoenix.Form.for_create(Basa.Catalog.Item, :create,
        actor: socket.assigns.current_user,
        as: "item"
      )

    open_form(socket, form, nil, [], %{})
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    item = Catalog.get_item!(id, actor: socket.assigns.current_user)

    form =
      AshPhoenix.Form.for_update(item, :update, actor: socket.assigns.current_user, as: "item")

    open_form(socket, form, item.category_id, item.photos, %{
      "title" => item.title,
      "brand" => item.brand,
      "model" => item.model,
      "description" => item.description,
      "no_photos" => to_string(item.no_photos)
    })
  end

  defp open_form(socket, form, category_id, photos, params) do
    socket
    |> assign(
      form: to_form(form),
      preview: nil,
      category: Enum.find(socket.assigns.categories, &(&1.id == category_id)),
      photos: photos,
      photo_notice: nil,
      suggestions: nil,
      recognizing?: false,
      no_photos?: params["no_photos"] == "true",
      pictures: nil,
      pictures_query: nil,
      pictures_listing: nil,
      searching_pictures?: false,
      picking: nil,
      listing_params: params
    )
    |> maybe_suggest_pictures(params)
  end

  defp maybe_suggest_pictures(socket, params) do
    a = socket.assigns

    listing = %{
      title: params["title"],
      brand: params["brand"],
      model: params["model"],
      description: params["description"],
      category: a.category
    }

    query =
      {listing.title, listing.brand, listing.model, a.category && a.category.id}
      |> then(fn {t, b, m, c} -> {trim(t), trim(b), trim(m), c} end)

    {title, brand, model, _} = query

    cond do
      not a.pictures? or a.photos != [] or a.no_photos? ->
        socket

      String.length(title) < 3 and brand == "" and model == "" ->
        assign(socket, pictures: nil, pictures_query: nil)

      query == a.pictures_query ->
        socket

      true ->
        socket
        |> assign(pictures_query: query, pictures_listing: listing, searching_pictures?: true)
        |> start_async(:pictures, fn -> Basa.Images.suggest(listing) end)
    end
  end

  defp trim(nil), do: ""
  defp trim(text), do: String.trim(text)

  defp load_items(socket),
    do: assign(socket, items: Catalog.list_my_items!(actor: socket.assigns.current_user))

  defp handle_progress(:photos, entry, socket) do
    if entry.done? do
      prefix = "items/#{socket.assigns.current_user.id}"

      case PhotoUploads.store(socket, entry, prefix, length(socket.assigns.photos), @max_photos) do
        {:stored, key} -> {:noreply, update(socket, :photos, &(&1 ++ [key]))}
        :full -> {:noreply, assign(socket, photo_notice: PhotoUploads.notice(@max_photos))}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("validate", %{"item" => params}, socket) do
    socket = maybe_switch_category(socket, params["category_id"])
    form = AshPhoenix.Form.validate(socket.assigns.form.source, prepare(params, socket))

    {:noreply,
     socket
     |> assign(form: to_form(form), listing_params: params)
     |> maybe_suggest_pictures(params)}
  end

  def handle_event("save", %{"item" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.form.source, params: prepare(params, socket)) do
      {:ok, _item} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Saved to your inventory."))
         |> load_items()
         |> push_patch(to: ~p"/my/items")}

      {:error, form} ->
        {:noreply, assign(socket, form: to_form(form))}
    end
  end

  def handle_event("validate_upload", _params, socket), do: {:noreply, socket}
  def handle_event("noop", _params, socket), do: {:noreply, socket}

  def handle_event("move_photo", %{"key" => key, "dir" => dir}, socket),
    do: {:noreply, update(socket, :photos, &BasaWeb.PhotoOrder.move(&1, key, dir))}

  def handle_event("reorder_photos", %{"keys" => keys}, socket),
    do: {:noreply, update(socket, :photos, &BasaWeb.PhotoOrder.reorder(&1, keys))}

  def handle_event("remove_photo", %{"key" => key}, socket) do
    {:noreply, socket |> update(:photos, &List.delete(&1, key)) |> assign(photo_notice: nil)}
  end

  def handle_event("cancel_upload", %{"ref" => ref}, socket),
    do: {:noreply, cancel_upload(socket, :photos, ref)}

  def handle_event("use_picture", %{"ref" => ref}, socket) do
    case Enum.find(socket.assigns.pictures || [], &(&1.ref == ref)) do
      nil ->
        {:noreply, socket}

      picture ->
        listing = socket.assigns.pictures_listing

        {:noreply,
         socket
         |> assign(picking: ref)
         |> start_async(:attach_picture, fn -> Basa.Images.attach(picture, listing) end)}
    end
  end

  def handle_event("no_pictures", _params, socket),
    do: {:noreply, socket |> assign(no_photos?: true, pictures: nil) |> revalidate()}

  def handle_event("suggest_pictures", _params, socket) do
    socket = socket |> assign(no_photos?: false, pictures_query: nil) |> revalidate()
    {:noreply, maybe_suggest_pictures(socket, socket.assigns.listing_params)}
  end

  def handle_event("recognize", _params, socket) do
    case socket.assigns.photos do
      [key | _] ->
        slugs = Enum.map(socket.assigns.categories, & &1.slug)

        {:noreply,
         socket
         |> assign(recognizing?: true, suggestions: nil)
         |> start_async(:recognize, fn ->
           with {:ok, body, type} <- Storage.get(key),
                do: Basa.AI.recognize(body, type, category_slugs: slugs)
         end)}

      [] ->
        {:noreply, put_flash(socket, :error, gettext("Add a photo first."))}
    end
  end

  def handle_event("use_suggestion", %{"index" => index}, socket) do
    s = Enum.at(socket.assigns.suggestions, String.to_integer(index))
    category = Enum.find(socket.assigns.categories, &(&1.slug == s.category_slug))

    params =
      socket.assigns.form.params
      |> Map.merge(%{
        "title" => s.title,
        "brand" => s.brand,
        "model" => s.model,
        "condition" => s.condition,
        "category_id" => category && category.id
      })

    socket = assign(socket, category: category)
    form = AshPhoenix.Form.validate(socket.assigns.form.source, prepare(params, socket))
    {:noreply, assign(socket, form: to_form(form), suggestions: nil)}
  end

  def handle_event("add_all_suggestions", _params, socket) do
    actor = socket.assigns.current_user

    created =
      for s <- socket.assigns.suggestions do
        category = Enum.find(socket.assigns.categories, &(&1.slug == s.category_slug))

        Catalog.create_item(
          %{
            title: s.title,
            brand: s.brand,
            model: s.model,
            condition: s.condition && String.to_existing_atom(s.condition),
            category_id: category && category.id,
            photos: socket.assigns.photos,
            ai_suggestion: Map.new(s, fn {k, v} -> {to_string(k), v} end)
          },
          actor: actor
        )
      end

    ok = Enum.count(created, &match?({:ok, _}, &1))

    {:noreply,
     socket
     |> put_flash(:info, gettext("Added %{n} items. Open each one to check the details.", n: ok))
     |> load_items()
     |> push_patch(to: ~p"/my/items")}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    actor = socket.assigns.current_user
    id |> Catalog.get_item!(actor: actor) |> Catalog.destroy_item!(actor: actor)
    {:noreply, socket |> put_flash(:info, gettext("Item removed.")) |> load_items()}
  end

  @impl true
  def handle_async(:recognize, {:ok, {:ok, suggestions}}, socket) do
    {:noreply, assign(socket, recognizing?: false, suggestions: suggestions)}
  end

  def handle_async(:pictures, {:ok, pictures}, socket),
    do: {:noreply, assign(socket, pictures: pictures, searching_pictures?: false)}

  def handle_async(:pictures, _result, socket),
    do: {:noreply, assign(socket, pictures: [], searching_pictures?: false)}

  def handle_async(:attach_picture, {:ok, {:ok, key}}, socket) do
    {:noreply,
     socket
     |> assign(picking: nil, pictures: nil, pictures_query: nil)
     |> update(:photos, &Enum.uniq(&1 ++ [key]))}
  end

  def handle_async(:attach_picture, _result, socket) do
    {:noreply,
     socket
     |> assign(picking: nil)
     |> put_flash(:error, gettext("Couldn't add that picture. Try another one."))}
  end

  def handle_async(:recognize, _result, socket) do
    {:noreply,
     socket
     |> assign(recognizing?: false)
     |> put_flash(:error, gettext("No suggestion this time. Fill in the details by hand."))}
  end

  defp maybe_switch_category(socket, id) do
    if socket.assigns.category && socket.assigns.category.id == id,
      do: socket,
      else: assign(socket, category: Enum.find(socket.assigns.categories, &(&1.id == id)))
  end

  defp prepare(params, socket) do
    schema = socket.assigns.category && socket.assigns.category.attr_schema

    params
    |> Map.put("photos", socket.assigns.photos)
    |> Map.put("no_photos", to_string(socket.assigns.no_photos?))
    |> Map.update("attrs", %{}, &JsonSchema.cast_params(schema, &1))
    |> Map.update("category_id", nil, &if(&1 == "", do: nil, else: &1))
  end

  defp revalidate(socket) do
    params =
      (socket.assigns.form.params || %{})
      |> Map.put("photos", socket.assigns.photos)
      |> Map.put("no_photos", to_string(socket.assigns.no_photos?))

    form = AshPhoenix.Form.validate(socket.assigns.form.source, params)
    assign(socket, form: to_form(form))
  end

  defp daily_hint(form) do
    case Decimal.parse(to_string(form[:estimated_value].value || "")) do
      {value, _} ->
        if Decimal.compare(value, 0) == :gt do
          gettext(
            "Suggested rent: about %{rate} per day (3% of value). You set the final price in the offer.",
            rate: Basa.Money.suggested_daily_rate(value) |> Decimal.to_string()
          )
        end

      _ ->
        nil
    end
  end

  attr :item, :map, required: true
  attr :credits, :list, required: true
  attr :widgets?, :boolean, required: true

  defp item_preview(assigns) do
    locale = Gettext.get_locale(BasaWeb.Gettext)
    item = assigns.item

    assigns =
      assign(assigns,
        category: item.category && Catalog.Category.display_name(item.category, locale),
        fields: Basa.JsonSchema.fields(item.category && item.category.attr_schema, locale),
        gallery: %{
          photos: Enum.map(item.photos, &%{src: Storage.url(&1), alt: item.title}),
          labels: %{
            open: gettext("Open photo"),
            close: gettext("Close"),
            previous: gettext("Previous photo"),
            next: gettext("Next photo"),
            more: gettext("+%{count}", count: "%{count}")
          }
        }
      )

    ~H"""
    <div id="item-preview-body">
      <div class="mb-1.5 flex flex-wrap items-center justify-between gap-2">
        <.back_button patch={~p"/my/items"} label={gettext("My items")} />
        <div class="flex items-center gap-2">
          <span id="item-preview-note" class="text-sm opacity-70">{gettext("Preview")}</span>
          <.info_tip id="item-preview-info" align="end">
            {gettext(
              "Renters see the item like this on its offer page once you make an offer of it; until then only you see it."
            )}
          </.info_tip>
          <.button_link
            id="item-preview-edit"
            patch={~p"/my/items/#{@item.id}/edit"}
            size="small"
            color="primary"
            variant="default"
            icon="hero-pencil-square"
          >
            {gettext("Edit")}
          </.button_link>
        </div>
      </div>

      <div class="mb-4">
        <.widget
          :if={@item.photos != []}
          id="item-preview-gallery"
          component="PhotoGallery"
          props={@gallery}
          enabled={@widgets?}
        >
          <:loading>
            <div class="aspect-video overflow-hidden rounded-xl">
              <.photo key={hd(@item.photos)} alt={@item.title} />
            </div>
          </:loading>
          <:fallback>
            <div class="aspect-video overflow-hidden rounded-xl">
              <.photo key={hd(@item.photos)} alt={@item.title} />
            </div>
            <div :if={length(@item.photos) > 1} class="mt-2 grid grid-cols-4 gap-2 sm:grid-cols-6">
              <a
                :for={key <- tl(@item.photos)}
                href={Storage.url(key)}
                target="_blank"
                class="aspect-square overflow-hidden rounded-lg"
              >
                <.photo key={key} alt={@item.title} />
              </a>
            </div>
          </:fallback>
        </.widget>
        <div :if={@item.photos == []} class="aspect-video overflow-hidden rounded-xl">
          <.photo key={List.first(@item.photos)} alt={@item.title} />
        </div>
        <.photo_credits id="item-preview-credits" credits={@credits} />
      </div>

      <div class="flex items-start justify-between gap-4">
        <div>
          <h1 class="text-2xl font-bold">{@item.title}</h1>
          <p
            :if={
              (@item.brand || @item.model) &&
                @item.title != String.trim("#{@item.brand} #{@item.model}")
            }
            class="opacity-70"
          >
            {@item.brand} {@item.model}
          </p>
          <p :if={@category} class="opacity-70">{@category}</p>
          <.badge :if={@item.sold_at} size="small" rounded="full" class="mt-1">
            {gettext("Sold")}
          </.badge>
        </div>
        <div :if={@item.estimated_value} class="shrink-0 text-right">
          <p class="text-xl font-bold">{Basa.Money.format(@item.estimated_value, @item.currency)}</p>
          <p class="text-sm opacity-70">{gettext("Market value")}</p>
        </div>
      </div>

      <p :if={@item.description} class="mt-4 whitespace-pre-line">{@item.description}</p>

      <dl class="mt-4 grid grid-cols-[auto_1fr] gap-x-4 gap-y-1">
        <%= if @item.condition do %>
          <dt class="opacity-70">{gettext("Condition")}</dt>
          <dd>{condition_label(@item.condition)}</dd>
        <% end %>
        <%= for f <- @fields, (v = (@item.attrs || %{})[f.name]) not in [nil, ""] do %>
          <dt class="opacity-70">{f.label}</dt>
          <dd>{attr_value(f, v)}</dd>
        <% end %>
      </dl>
    </div>
    """
  end

  defp condition_label(:new), do: gettext("New")
  defp condition_label(:excellent), do: gettext("Excellent")
  defp condition_label(:good), do: gettext("Good")
  defp condition_label(:fair), do: gettext("Fair")
  defp condition_label(:worn), do: gettext("Worn")

  defp attr_value(%{type: :checkbox}, v),
    do: if(v in [true, "true"], do: gettext("Yes"), else: gettext("No"))

  defp attr_value(f, v) do
    text = Map.get(f.enum_labels || %{}, to_string(v), to_string(v))
    if f.unit, do: "#{text} #{f.unit}", else: text
  end

  defp attrs_errors(form) do
    form.source
    |> AshPhoenix.Form.errors(for_path: [])
    |> Keyword.get_values(:attrs)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} unread={@unread_count} active={:my}>
      <.item_preview :if={@preview} item={@preview} credits={@preview_credits} widgets?={@widgets?} />

      <div :if={!@preview}>
        <.page_title title={gettext("My items")}>
          <:action>
            <.button_link
              patch={~p"/my/items/new"}
              size="small"
              color="primary"
              variant="default"
              icon="hero-camera"
            >
              {gettext("Add item")}
            </.button_link>
          </:action>
        </.page_title>

        <div class="grid grid-cols-2 gap-3 sm:grid-cols-3">
          <.card :for={item <- @items} padding="none" rounded="large" class="overflow-hidden">
            <div class="relative aspect-square">
              <.photo key={List.first(item.photos)} alt={item.title} />
              <span
                :if={item.sold_at}
                class="absolute top-2 left-2 rounded-full bg-black/70 px-2 py-0.5 text-xs font-medium text-white"
              >
                {gettext("Sold")}
              </span>
            </div>
            <.card_content padding="small" class="space-y-1">
              <p class="line-clamp-2 text-sm font-medium">{item.title}</p>
              <p class="text-xs opacity-70">
                {item.category &&
                  Basa.Catalog.Category.display_name(
                    item.category,
                    Gettext.get_locale(BasaWeb.Gettext)
                  )}
              </p>
              <p :if={item.estimated_value} class="text-xs">
                {Basa.Money.format(item.estimated_value, item.currency)}
              </p>
              <div class="flex justify-end gap-1">
                <.button_link
                  id={"preview-#{item.id}"}
                  patch={~p"/my/items/#{item.id}"}
                  size="extra_small"
                  variant="transparent"
                  icon="hero-eye"
                  aria-label={gettext("Preview")}
                  title={gettext("Preview")}
                />
                <.button_link
                  patch={~p"/my/items/#{item.id}/edit"}
                  size="extra_small"
                  variant="bordered"
                >{gettext("Edit")}</.button_link>
                <.button
                  phx-click="delete"
                  phx-value-id={item.id}
                  data-confirm={gettext("Remove this item?")}
                  size="extra_small"
                  variant="transparent"
                  icon="hero-trash"
                  aria-label={gettext("Remove")}
                />
              </div>
            </.card_content>
          </.card>
        </div>
        <.empty_state :if={@items == []} title={gettext("Your inventory is empty")} icon="hero-camera">
          {gettext("Take a few photos of what you rent out. We'll help fill in the rest.")}
        </.empty_state>
      </div>

      <.modal
        :if={@form}
        id="item-dialog"
        show
        title={if @live_action == :edit, do: gettext("Edit item"), else: gettext("Add item")}
        on_cancel={JS.patch(~p"/my/items")}
        size="large"
        rounded="large"
      >
        <section>
          <p class="mb-2 font-medium">1. {gettext("Photos")}</p>
          <.photo_uploader
            id="item-photos"
            upload={@uploads.photos}
            photos={@photos}
            max={@max_photos}
            notice={@photo_notice}
          />

          <div :if={@ai? and @photos != []} class="mt-3">
            <.button
              type="button"
              phx-click="recognize"
              size="small"
              color="secondary"
              variant="default"
              icon={if !@recognizing?, do: "hero-sparkles"}
              disabled={@recognizing?}
            >
              <.spinner :if={@recognizing?} size="extra_small" />
              {gettext("Suggest from photo")}
            </.button>
          </div>

          <div :if={@suggestions} class="mt-3 space-y-2">
            <p class="text-sm opacity-70">{gettext("Suggestions. Check them before saving:")}</p>
            <.card
              :for={{s, i} <- Enum.with_index(@suggestions)}
              padding="small"
              rounded="large"
              class="flex items-center justify-between gap-2"
            >
              <div class="text-sm">
                <p class="font-medium">{s.title}</p>
                <p class="opacity-70">{s.brand} {s.model} · {round(s.confidence * 100)}%</p>
                <p :if={s.notes} class="text-xs opacity-70">{s.notes}</p>
              </div>
              <.button
                type="button"
                size="extra_small"
                variant="bordered"
                phx-click="use_suggestion"
                phx-value-index={i}
              >{gettext("Use")}</.button>
            </.card>
            <.button
              :if={length(@suggestions) > 1 and @live_action == :new}
              type="button"
              size="extra_small"
              variant="bordered"
              phx-click="add_all_suggestions"
            >
              {gettext("Add all %{n} as separate items", n: length(@suggestions))}
            </.button>
            <p :if={@suggestions == []} class="text-sm">
              {gettext("Nothing recognized. Fill in the details by hand.")}
            </p>
          </div>

          <div
            :if={@pictures? and @photos == [] and !@no_photos? and @uploads.photos.entries == []}
            id="picture-suggestions"
            class="mt-4 space-y-2"
          >
            <div class="flex items-center justify-between gap-2">
              <p class="flex items-center gap-1 text-sm font-medium">
                {gettext("No photos yet? Pictures that may fit")}
                <.info_tip id="pictures-info">
                  {gettext(
                    "Openly licensed pictures of similar things. Renters see them marked as illustrations, with the author's credit. Your own photos show your item best."
                  )}
                </.info_tip>
              </p>
              <.button
                id="no-pictures"
                type="button"
                phx-click="no_pictures"
                size="extra_small"
                variant="transparent"
              >
                {gettext("No pictures")}
              </.button>
            </div>
            <p :if={@searching_pictures?} class="flex items-center gap-2 text-sm opacity-70">
              <.spinner size="extra_small" /> {gettext("Looking for pictures…")}
            </p>
            <p :if={!@searching_pictures? and is_nil(@pictures)} class="text-sm opacity-70">
              {gettext("Type a title to see pictures that may fit.")}
            </p>
            <p :if={!@searching_pictures? and @pictures == []} class="text-sm opacity-70">
              {gettext("No pictures found. Add your own photos.")}
            </p>
            <div :if={@pictures not in [nil, []]} id="picture-grid" phx-hook="BrokenPictures">
              <div class="grid grid-cols-3 gap-2 sm:grid-cols-4">
                <div :for={{p, i} <- Enum.with_index(@pictures)} data-picture class="min-w-0">
                  <button
                    type="button"
                    id={"picture-#{i}"}
                    phx-click="use_picture"
                    phx-value-ref={p.ref}
                    disabled={not is_nil(@picking)}
                    class="relative block aspect-square w-full cursor-pointer overflow-hidden rounded-lg bg-zinc-100 disabled:cursor-wait dark:bg-zinc-800"
                    aria-label={gettext("Use this picture")}
                    title={gettext("Use this picture")}
                  >
                    <img
                      src={p.thumbnail}
                      alt={p.title || ""}
                      loading="lazy"
                      referrerpolicy="no-referrer"
                      class="h-full w-full object-cover"
                    />
                    <span
                      :if={@picking == p.ref}
                      class="absolute inset-0 flex items-center justify-center bg-black/40"
                    >
                      <.spinner size="small" />
                    </span>
                  </button>
                  <p class="mt-0.5 truncate text-[11px] opacity-70">
                    <.picture_credit picture={p} short />
                  </p>
                </div>
              </div>
              <p data-pictures-none hidden class="text-sm opacity-70">
                {gettext("No pictures found. Add your own photos.")}
              </p>
            </div>
          </div>
          <p
            :if={@pictures? and @photos == [] and @no_photos?}
            id="pictures-off"
            class="mt-3 flex flex-wrap items-center gap-2 text-sm opacity-70"
          >
            {gettext("No pictures are suggested for this item.")}
            <.button
              type="button"
              phx-click="suggest_pictures"
              size="extra_small"
              variant="transparent"
            >
              {gettext("Suggest pictures")}
            </.button>
          </p>
        </section>

        <.form
          for={@form}
          id="item-form"
          phx-change="validate"
          phx-submit="save"
          class="mt-5 space-y-3"
        >
          <p class="font-medium">2. {gettext("Details")}</p>
          <.text_field
            field={@form[:title]}
            label={gettext("Title")}
            placeholder="Shure SM7B"
            size="medium"
          />
          <div class="grid grid-cols-2 gap-3">
            <.text_field field={@form[:brand]} label={gettext("Brand")} size="medium" />
            <.text_field field={@form[:model]} label={gettext("Model")} size="medium" />
          </div>
          <.native_select field={@form[:category_id]} label={gettext("Category")} size="medium">
            <:option value="">{gettext("Choose…")}</:option>
            <:option
              :for={c <- @categories}
              value={c.id}
              selected={to_string(@form[:category_id].value) == c.id}
            >
              {Basa.Catalog.Category.display_name(c, Gettext.get_locale(BasaWeb.Gettext))}
            </:option>
          </.native_select>
          <.schema_fields
            :if={@category}
            schema={@category.attr_schema}
            values={@form[:attrs].value || %{}}
            prefix="item[attrs]"
            errors={attrs_errors(@form)}
          />
          <.native_select field={@form[:condition]} label={gettext("Condition")} size="medium">
            <:option
              :for={
                {label, v} <- [
                  {gettext("New"), :new},
                  {gettext("Excellent"), :excellent},
                  {gettext("Good"), :good},
                  {gettext("Fair"), :fair},
                  {gettext("Worn"), :worn}
                ]
              }
              value={v}
              selected={to_string(@form[:condition].value) == to_string(v)}
            >
              {label}
            </:option>
          </.native_select>
          <div class="grid grid-cols-3 gap-3">
            <div class="col-span-2">
              <.number_field
                field={@form[:estimated_value]}
                label={gettext("Market value")}
                min="0"
                step="1"
                size="medium"
              />
            </div>
            <.native_select field={@form[:currency]} label={gettext("Currency")} size="medium">
              <:option
                :for={c <- Basa.Money.currencies()}
                value={c}
                selected={to_string(@form[:currency].value) == to_string(c)}
              >
                {c}
              </:option>
            </.native_select>
          </div>
          <p :if={daily_hint(@form)} class="text-sm opacity-70">{daily_hint(@form)}</p>
          <.textarea_field field={@form[:description]} label={gettext("Notes for renters")} rows="3" />

          <div class="flex justify-end gap-2 pt-2">
            <.button_link patch={~p"/my/items"} variant="transparent">{gettext("Cancel")}</.button_link>
            <.button
              type="submit"
              color="primary"
              variant="default"
              phx-disable-with={gettext("Saving…")}
            >{gettext("Save")}</.button>
          </div>
        </.form>
      </.modal>
    </Layouts.app>
    """
  end
end
