defmodule BasaWeb.BasaComponents do
  use Phoenix.Component
  use Gettext, backend: BasaWeb.Gettext

  use Phoenix.VerifiedRoutes,
    endpoint: BasaWeb.Endpoint,
    router: BasaWeb.Router,
    statics: BasaWeb.static_paths()

  use BasaWeb.Components.MishkaComponents

  attr :steps, :list, required: true
  attr :current, :integer, required: true

  def wizard_steps(assigns) do
    ~H"""
    <.stepper size="small" color="primary" margin="none" col_step class="mb-6">
      <.stepper_section
        :for={{label, i} <- Enum.with_index(@steps)}
        step={
          cond do
            i < @current -> "completed"
            i == @current -> "current"
            true -> "none"
          end
        }
        step_number={i + 1}
        title={label}
        size="small"
      />
    </.stepper>
    """
  end

  attr :title, :string, required: true
  attr :level, :integer, default: 1
  attr :info_id, :string, default: "page-info"
  attr :help, :string, default: nil, doc: "a help topic (`BasaWeb.Help`): a \"?\" link to it"
  slot :action
  slot :info

  def page_title(assigns) do
    ~H"""
    <div class="mb-4 flex items-center justify-between gap-3">
      <div class="flex min-w-0 items-center gap-1.5">
        <h1 :if={@level == 1} class="text-2xl font-bold">{@title}</h1>
        <h2 :if={@level != 1} class="font-semibold">{@title}</h2>
        <.info_tip :if={@info != []} id={@info_id}>{render_slot(@info)}</.info_tip>
        <.help_link :if={@help} topic={@help} />
      </div>
      <div :if={@action != []}>{render_slot(@action)}</div>
    </div>
    """
  end

  attr :topic, :string, required: true

  def help_link(assigns) do
    ~H"""
    <a
      href={"/help/#{@topic}"}
      target="_blank"
      id={"help-link-#{@topic}"}
      class="inline-flex size-5 items-center justify-center rounded-full border border-current text-xs font-semibold opacity-60 hover:opacity-100"
      title={gettext("Help")}
      aria-label={gettext("Help")}
    >?</a>
    """
  end

  attr :options, :list, required: true, doc: "[{value, label}] or [{value, label, sub}]"
  attr :selected, :any, required: true
  attr :event, :string, required: true
  attr :key, :string, default: "choice"
  attr :cols, :string, default: "grid-cols-2"

  def choice_buttons(assigns) do
    ~H"""
    <div class={["grid gap-2", @cols]}>
      <.button
        :for={option <- @options}
        type="button"
        phx-click={@event}
        {%{"phx-value-#{@key}" => to_string(elem(option, 0))}}
        variant={
          if to_string(elem(option, 0)) == to_string(@selected), do: "default", else: "bordered"
        }
        color={if to_string(elem(option, 0)) == to_string(@selected), do: "primary", else: "natural"}
        size="medium"
        full_width
      >
        <span class="flex flex-col items-center leading-tight">
          <span :if={tuple_size(option) == 3} class="text-base">{elem(option, 2)}</span>
          <span>{elem(option, 1)}</span>
        </span>
      </.button>
    </div>
    """
  end

  attr :schema, :map, default: %{}
  attr :values, :map, default: %{}
  attr :prefix, :string, default: "attrs"
  attr :errors, :list, default: []

  def schema_fields(assigns) do
    assigns = assign(assigns, :fields, Basa.JsonSchema.fields(assigns.schema))

    ~H"""
    <div :if={@fields != []} class="grid gap-3 sm:grid-cols-2">
      <div :for={f <- @fields}>
        <%= case f.type do %>
          <% :checkbox -> %>
            <.toggle_field
              id={"#{@prefix}-#{f.name}" |> String.replace(~r/[^\w-]/, "_")}
              name={"#{@prefix}[#{f.name}]"}
              label={f.label}
              description={f.help}
              checked={@values[f.name] in [true, "true"]}
              size="small"
            />
          <% :select -> %>
            <.native_select
              id={"#{@prefix}-#{f.name}" |> String.replace(~r/[^\w-]/, "_")}
              name={"#{@prefix}[#{f.name}]"}
              label={label(f)}
              description={f.help}
              size="medium"
            >
              <:option value="">{gettext("Choose…")}</:option>
              <:option :for={opt <- f.enum} value={opt} selected={@values[f.name] == opt}>
                {Map.get(f.enum_labels, opt, opt)}
              </:option>
            </.native_select>
          <% :number -> %>
            <.number_field
              name={"#{@prefix}[#{f.name}]"}
              value={@values[f.name]}
              label={label(f)}
              description={f.help}
              min={f.min}
              max={f.max}
              step={f.step}
              size="medium"
            >
              <:end_section :if={f.unit}>
                <span class="text-sm opacity-70">{f.unit}</span>
              </:end_section>
            </.number_field>
          <% _ -> %>
            <.text_field
              name={"#{@prefix}[#{f.name}]"}
              value={@values[f.name]}
              label={label(f)}
              description={f.help}
              size="medium"
            />
        <% end %>
      </div>
    </div>
    <ul :if={@errors != []} class="mt-2 text-sm text-rose-600 dark:text-rose-400">
      <li :for={e <- @errors}>{e}</li>
    </ul>
    """
  end

  defp label(%{label: l, required?: true}), do: l <> " *"
  defp label(%{label: l}), do: l

  attr :state, :atom, required: true

  def state_badge(assigns) do
    ~H"""
    <.badge size="small" rounded="full" variant="default" color={state_color(@state)}>
      {state_label(@state)}
    </.badge>
    """
  end

  defp state_color(s) when s in [:published, :confirmed, :sealed, :closed, :settled],
    do: "success"

  defp state_color(s) when s in [:under_review, :pending, :signing, :returned, :claimed],
    do: "warning"

  defp state_color(:disputed), do: "danger"
  defp state_color(:completed), do: "info"
  defp state_color(s) when s in [:declined, :cancelled], do: "danger"
  defp state_color(_), do: "natural"

  def state_label(:draft), do: gettext("Draft")
  def state_label(:under_review), do: gettext("Under review")
  def state_label(:published), do: gettext("Published")
  def state_label(:archived), do: gettext("Archived")
  def state_label(:pending), do: gettext("Waiting for lessor")
  def state_label(:confirmed), do: gettext("Confirmed")
  def state_label(:declined), do: gettext("Declined")
  def state_label(:cancelled), do: gettext("Cancelled")
  def state_label(:completed), do: gettext("Completed")
  def state_label(:signing), do: gettext("Signing")
  def state_label(:sealed), do: gettext("Sealed")
  def state_label(:returned), do: gettext("Returned")
  def state_label(:claimed), do: gettext("Claim open")
  def state_label(:settled), do: gettext("Settled")
  def state_label(:closed), do: gettext("Closed")
  def state_label(:disputed), do: gettext("Disputed")
  def state_label(other), do: to_string(other)

  def unit_label(:hour), do: gettext("hour")
  def unit_label(:day), do: gettext("day")
  def unit_label(:slot), do: gettext("slot")

  attr :id, :string, required: true
  attr :label, :string, default: nil, doc: "what screen readers announce for the icon"
  attr :align, :string, default: "start", values: ~w(start end)
  attr :class, :any, default: nil
  slot :inner_block, required: true

  def info_tip(assigns) do
    ~H"""
    <span id={@id} class={["group/info relative inline-flex align-middle", @class]}>
      <span
        role="button"
        tabindex="0"
        aria-label={@label || gettext("More information")}
        aria-describedby={"#{@id}-text"}
        class="inline-flex cursor-help rounded-full opacity-60 outline-none hover:opacity-100 focus:opacity-100 focus-visible:ring-2 focus-visible:ring-current"
      >
        <.icon name="hero-information-circle" class="size-4" />
      </span>
      <span
        id={"#{@id}-text"}
        role="tooltip"
        class={[
          "invisible absolute top-full z-50 mt-1 w-64 max-w-[80vw] rounded-lg border border-zinc-200 bg-white p-2 text-xs font-normal leading-snug text-zinc-700 opacity-0 shadow-lg transition-opacity",
          "group-hover/info:visible group-hover/info:opacity-100 group-focus-within/info:visible group-focus-within/info:opacity-100",
          "dark:border-zinc-700 dark:bg-zinc-800 dark:text-zinc-200",
          if(@align == "end", do: "right-0", else: "left-0")
        ]}
      >
        {render_slot(@inner_block)}
      </span>
    </span>
    """
  end

  attr :picture, :map, required: true
  attr :short, :boolean, default: false

  def picture_credit(assigns) do
    ~H"""
    <span :if={@short}>
      {[@picture.creator, license_label(@picture)]
      |> Enum.reject(&(&1 in [nil, ""]))
      |> Enum.join(" · ")}
    </span>
    <span :if={!@short}>
      <a
        :if={@picture.landing_url}
        href={@picture.landing_url}
        target="_blank"
        rel="noopener nofollow"
        class="underline"
      >{@picture.title || gettext("Picture")}</a><span :if={!@picture.landing_url}>{@picture.title ||
        gettext("Picture")}</span><span :if={@picture.creator}>, {gettext("by %{author}", author: @picture.creator)}</span>,
      <a
        :if={@picture.license_url}
        href={@picture.license_url}
        target="_blank"
        rel="noopener license"
        class="underline"
      >{license_label(@picture)}</a><span :if={!@picture.license_url}>{license_label(@picture)}</span>
    </span>
    """
  end

  @doc ~S|"CC BY 2.0", "CC0", "Public domain".|
  def license_label(%{license: "cc0"}), do: "CC0"
  def license_label(%{license: "pdm"}), do: gettext("Public domain")

  def license_label(%{license: l} = p),
    do: String.trim("CC #{String.upcase(l)} #{Map.get(p, :license_version)}")

  attr :id, :string, required: true
  attr :credits, :list, required: true

  def photo_credits(assigns) do
    ~H"""
    <div :if={@credits != []} id={@id} class="mt-2 text-xs opacity-70">
      <p>{gettext("Illustrations, not photos of this item:")}</p>
      <ul class="list-inside list-disc">
        <li :for={c <- @credits}><.picture_credit picture={c} /></li>
      </ul>
    </div>
    """
  end

  attr :view, :map, required: true

  def street_view_credit(assigns) do
    ~H"""
    <p class="text-xs opacity-70">
      <a href={Basa.StreetView.link(@view)} target="_blank" rel="noopener nofollow" class="underline">
        {gettext("Street view")}
      </a><span :if={@view["creator"]}>, {gettext("by %{author}", author: @view["creator"])}</span><span :if={
        @view["captured_at"]
      }> ({String.slice(@view["captured_at"], 0, 4)})</span>,
      Mapillary,
      <a
        href="https://creativecommons.org/licenses/by-sa/4.0/"
        target="_blank"
        rel="noopener license"
        class="underline"
      >CC BY-SA 4.0</a>
    </p>
    """
  end

  attr :key, :string, default: nil
  attr :class, :string, default: "w-full h-full object-cover"
  attr :alt, :string, default: ""

  def photo(assigns) do
    ~H"""
    <img :if={@key} src={Basa.Storage.url(@key)} alt={@alt} class={@class} loading="lazy" />
    <div
      :if={!@key}
      class={["flex items-center justify-center bg-zinc-100 text-zinc-400 dark:bg-zinc-800", @class]}
    >
      <.icon name="hero-photo" class="size-8" />
    </div>
    """
  end

  attr :lot, :map, required: true

  def lot_card(assigns) do
    assigns = assign(assigns, :cover, cover(assigns.lot))

    ~H"""
    <.link navigate={~p"/lots/#{@lot.id}"} class="block transition hover:-translate-y-0.5">
      <.card rounded="large" padding="none" class="flex overflow-hidden">
        <div class="w-28 shrink-0 sm:w-36">
          <div class="relative h-full w-full">
            <.photo key={@cover} alt={@lot.title} class="h-full w-full object-cover" />
            <span
              :if={@cover && Basa.Images.stock?(@cover)}
              class="absolute bottom-1 left-1 rounded bg-black/60 px-1 text-[10px] text-white"
            >
              {gettext("Illustration")}
            </span>
          </div>
        </div>
        <.card_content padding="small" class="space-y-1">
          <h3 class="font-semibold">
            {@lot.title}
            <.badge
              :if={Map.get(@lot, :featured) == true}
              color="warning"
              size="extra_small"
              rounded="full"
              variant="default"
            >
              ★ {gettext("Featured")}
            </.badge>
          </h3>
          <p class="text-sm opacity-70">
            {city_name(@lot.room)}
            <.badge :if={@lot.room.mobile} size="extra_small" variant="bordered" rounded="full">
              {gettext("mobile")}
            </.badge>
            <span class="ml-1 opacity-60">{Basa.Catalog.Room.placement_marker(@lot.room.placement)}</span>
          </p>
          <p class="line-clamp-1 text-sm opacity-70">
            {Enum.map_join(@lot.basket.items, ", ", & &1.title)}
          </p>
          <p class="font-semibold">
            {Basa.Money.format(@lot.price_amount, @lot.currency)}
            <span :if={@lot.deal != :sale} class="text-sm font-normal opacity-70">
              / {unit_label(@lot.price_unit)}
            </span>
            <span
              :if={@lot.deal == :sale}
              class="ml-1 rounded-full bg-secondary-bordered-bg-light px-2 py-0.5 text-xs font-medium text-secondary-bordered-text-light dark:bg-secondary-bordered-bg-dark dark:text-secondary-bordered-text-dark"
            >
              {gettext("For sale")}
            </span>
          </p>
        </.card_content>
      </.card>
    </.link>
    """
  end

  attr :id, :string, required: true
  attr :component, :string, required: true
  attr :props, :map, default: %{}
  attr :enabled, :boolean, required: true
  attr :class, :any, default: nil
  slot :loading, doc: "Shown until the widget has loaded"
  slot :fallback, required: true, doc: "The server-rendered version when widgets are off"

  def widget(%{enabled: false} = assigns) do
    ~H"""
    <div id={@id} class={@class}>{render_slot(@fallback)}</div>
    """
  end

  def widget(assigns) do
    ~H"""
    <div
      id={@id}
      phx-hook="Widget"
      data-component={@component}
      data-props={Jason.encode!(@props)}
      class={@class}
    >
      <div id={"#{@id}-root"} data-widget-root phx-update="ignore">{render_slot(@loading)}</div>
    </div>
    """
  end

  def city_name(%{geo_city: %Basa.Geo.City{} = city}),
    do: Basa.Geo.City.display_name(city, Gettext.get_locale(BasaWeb.Gettext))

  def city_name(%{city: city}), do: city

  attr :navigate, :string, default: nil
  attr :patch, :string, default: nil
  attr :label, :string, required: true
  attr :class, :any, default: nil
  attr :rest, :global

  def back_button(assigns) do
    ~H"""
    <.link
      navigate={@navigate}
      patch={@patch}
      aria-label={@label}
      class={[
        "basa-round-btn group inline-flex h-9 items-center rounded-full shadow-sm outline-none transition-colors",
        "focus-visible:ring-2 focus-visible:ring-offset-2 focus-visible:ring-primary-light",
        @class
      ]}
      {@rest}
    >
      <span class="flex size-9 shrink-0 items-center justify-center">
        <.brand_icon name="left" class="size-4 -translate-x-px" />
      </span>
      <span class="basa-round-label max-w-0 overflow-hidden whitespace-nowrap opacity-0 transition-all duration-200 ease-out group-hover:max-w-48 group-hover:pr-4 group-hover:opacity-100 group-focus-visible:max-w-48 group-focus-visible:pr-4 group-focus-visible:opacity-100">
        {@label}
      </span>
    </.link>
    """
  end

  attr :name, :string, required: true, values: ~w(up down left right left-alt right-alt)
  attr :class, :any, default: "size-4"

  def brand_icon(assigns) do
    ~H"""
    <span class={["brand-icon", "brand-icon-#{@name}", @class]} aria-hidden="true"></span>
    """
  end

  attr :id, :string, required: true
  attr :upload, :any, required: true, doc: "the `Phoenix.LiveView.UploadConfig`"
  attr :photos, :list, required: true
  attr :max, :integer, required: true
  attr :change, :string, default: "validate_upload"
  attr :notice, :string, default: nil

  def photo_uploader(assigns) do
    assigns =
      assign(assigns,
        full?: length(assigns.photos) + length(assigns.upload.entries) >= assigns.max
      )

    ~H"""
    <div id={@id} phx-hook="ThumbSize" class="space-y-2">
      <div class="flex flex-wrap items-center justify-between gap-2 text-xs">
        <span id={"#{@id}-count"} class="opacity-70">
          {gettext("%{count} of %{max} photos", count: length(@photos), max: @max)}
        </span>
        <label
          :if={@photos != []}
          id={"#{@id}-size"}
          phx-update="ignore"
          class="flex items-center gap-1.5 opacity-80"
          title={gettext("Photo size")}
        >
          <.icon name="hero-photo" class="size-3.5" />
          <input
            type="range"
            min="56"
            max="224"
            step="8"
            value="80"
            data-thumb-size
            aria-label={gettext("Photo size")}
            class="w-28 accent-[var(--ui-action)]"
          />
          <.icon name="hero-photo" class="size-5" />
        </label>
      </div>
      <div class="flex flex-wrap gap-2">
        <.photo_strip id={"#{@id}-strip"} photos={@photos} />
        <div
          :for={entry <- @upload.entries}
          class="flex size-[var(--thumb,5rem)] flex-col items-center justify-center gap-1 rounded-lg bg-zinc-100 p-1 text-center text-xs dark:bg-zinc-800"
        >
          <%= case upload_errors(@upload, entry) do %>
            <% [] -> %>
              <.progress value={entry.progress} size="small" color="primary" class="w-4/5" />
            <% [err | _] -> %>
              <span class="text-rose-600">{photo_upload_error(err)}</span>
          <% end %>
          <button
            type="button"
            phx-click="cancel_upload"
            phx-value-ref={entry.ref}
            class="cursor-pointer underline"
          >{gettext("cancel")}</button>
        </div>
        <form id={"#{@id}-form"} phx-change={@change} phx-submit="noop" class={@full? && "hidden"}>
          <label class="flex size-[var(--thumb,5rem)] cursor-pointer flex-col items-center justify-center rounded-lg border-2 border-dashed border-zinc-300 text-xs opacity-80 dark:border-zinc-700">
            <.icon name="hero-camera" class="size-6" />
            {gettext("Add")}
            <.live_file_input upload={@upload} class="hidden" />
          </label>
        </form>
      </div>
      <p :for={err <- upload_errors(@upload)} class="text-sm text-rose-600">
        {photo_upload_error(err, @max)}
      </p>
      <p :if={@notice} id={"#{@id}-notice"} class="text-sm text-amber-700 dark:text-amber-400">
        {@notice}
      </p>
    </div>
    """
  end

  defp photo_upload_error(err, max \\ nil)
  defp photo_upload_error(:too_large, _), do: gettext("That photo is too large (max 12 MB).")

  defp photo_upload_error(:too_many_files, max),
    do: gettext("Up to %{max} photos.", max: max || "")

  defp photo_upload_error(:not_accepted, _), do: gettext("Use JPG, PNG or WebP photos.")
  defp photo_upload_error(_, _), do: gettext("Upload failed.")

  attr :id, :string, required: true
  attr :photos, :list, required: true

  def photo_strip(assigns) do
    ~H"""
    <div id={@id} phx-hook="PhotoSort" class="contents">
      <div
        :for={{key, i} <- Enum.with_index(@photos)}
        data-sort-key={key}
        class="group relative size-[var(--thumb,5rem)] cursor-grab overflow-hidden rounded-lg active:cursor-grabbing"
      >
        <.photo key={key} />
        <span
          :if={Basa.Images.stock?(key)}
          class="absolute right-1 bottom-1 max-w-[4.5rem] truncate rounded bg-black/60 px-1 text-[10px] text-white"
        >
          {gettext("Illustration")}
        </span>
        <span
          :if={i == 0 and length(@photos) > 1}
          class="absolute bottom-1 left-1 flex rounded bg-black/60 p-0.5 text-amber-300"
          title={gettext("Cover")}
        >
          <.icon name="hero-star-solid" class="size-3" />
          <span class="sr-only">{gettext("Cover")}</span>
        </span>
        <button
          type="button"
          phx-click="remove_photo"
          phx-value-key={key}
          class="absolute top-1 right-1 cursor-pointer rounded-full bg-white/90 p-0.5 text-zinc-800"
          aria-label={gettext("Remove photo")}
        >
          <.icon name="hero-x-mark" class="size-4" />
        </button>
        <div :if={length(@photos) > 1} class="absolute bottom-1 right-1 flex gap-0.5">
          <button
            :if={i > 0}
            type="button"
            phx-click="move_photo"
            phx-value-key={key}
            phx-value-dir="left"
            class="flex cursor-pointer rounded bg-white/90 p-0.5 text-zinc-800"
            aria-label={gettext("Move left")}
          >
            <.brand_icon name="left" class="size-3.5" />
          </button>
          <button
            :if={i < length(@photos) - 1}
            type="button"
            phx-click="move_photo"
            phx-value-key={key}
            phx-value-dir="right"
            class="flex cursor-pointer rounded bg-white/90 p-0.5 text-zinc-800"
            aria-label={gettext("Move right")}
          >
            <.brand_icon name="right" class="size-3.5" />
          </button>
        </div>
      </div>
    </div>
    """
  end

  def photos(lot) do
    room = (lot.room && lot.room.photos) || []
    items = Enum.flat_map((lot.basket && lot.basket.items) || [], &(&1.photos || []))
    Enum.uniq(room ++ items)
  end

  def cover(%{room: %{photos: [key | _]}}), do: key

  def cover(%{basket: %{items: items}}) when is_list(items),
    do: Enum.find_value(items, &List.first(&1.photos))

  def cover(_), do: nil

  attr :title, :string, required: true
  attr :icon, :string, default: "hero-sparkles"
  attr :class, :any, default: nil
  slot :inner_block
  slot :action

  def empty_state(assigns) do
    ~H"""
    <div class={[
      "rounded-xl border border-dashed border-zinc-300 p-8 text-center dark:border-zinc-700",
      @class
    ]}>
      <.icon name={@icon} class="size-8 opacity-50" />
      <p class="mt-2 font-medium">{@title}</p>
      <div class="text-sm opacity-70">{render_slot(@inner_block)}</div>
      <div :if={@action != []} class="mt-4">{render_slot(@action)}</div>
    </div>
    """
  end

  attr :selected, :boolean, default: false
  attr :rest, :global, include: ~w(phx-click phx-value-id phx-value-kind phx-value-field)
  slot :inner_block, required: true

  def select_card(assigns) do
    ~H"""
    <button
      type="button"
      class={[
        "w-full cursor-pointer overflow-hidden rounded-xl border text-left transition",
        if(@selected,
          do:
            "border-primary-light ring-2 ring-primary-light dark:border-primary-dark dark:ring-primary-dark",
          else: "border-zinc-200 hover:border-zinc-400 dark:border-zinc-700"
        )
      ]}
      aria-pressed={to_string(@selected)}
      {@rest}
    >
      {render_slot(@inner_block)}
    </button>
    """
  end
end
