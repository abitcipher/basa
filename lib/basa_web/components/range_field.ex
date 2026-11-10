defmodule BasaWeb.Components.RangeField do
  use Phoenix.Component
  import BasaWeb.Components.Icon, only: [icon: 1]

  @doc type: :component
  attr :id, :string,
    default: nil,
    doc: "A unique identifier is used to manage state and interaction"

  attr :class, :any, default: nil, doc: "Custom CSS class for additional styling"
  attr :label_class, :string, default: nil, doc: "Custom CSS class for the label styling"
  attr :color, :string, default: "primary", doc: "Determines color theme"
  attr :border, :string, default: "extra_small", doc: "Determines border style"

  attr :size, :string,
    default: "extra_small",
    doc:
      "Determines the overall size of the elements, including padding, font size, and other items"

  attr :appearance, :string, default: "default", doc: "custom, default"
  attr :width, :string, default: "full", doc: "Determines the element width"

  attr :ring, :boolean,
    default: true,
    doc:
      "Determines a ring border on focused input, utilities for creating outline rings with box-shadows."

  attr :reverse, :boolean, default: false, doc: "Switches the order of the element and label"
  attr :checked, :boolean, default: false, doc: "Specifies if the element is checked by default"
  attr :error_icon, :string, default: nil, doc: "Icon to be displayed alongside error messages"
  attr :label, :string, default: nil, doc: "Specifies text for the label"
  attr :errors, :list, default: [], doc: "List of error messages to be displayed"
  attr :name, :any, default: nil, doc: "Name of input"
  attr :value, :any, default: nil, doc: "Value of input"

  attr :field, Phoenix.HTML.FormField, doc: "a form field struct retrieved from the form"

  attr :rest, :global,
    include: ~w(autocomplete disabled form readonly min max step required title autofocus),
    doc:
      "Global attributes can define defaults which are merged with attributes provided by the caller"

  slot :range_value, required: false do
    attr :class, :any, doc: "Custom CSS class for additional styling"

    attr :position, :any,
      required: false,
      doc: "Determines the element position, `start` when not given"
  end

  @spec range_field(map()) :: Phoenix.LiveView.Rendered.t()
  def range_field(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []

    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(errors, &translate_error(&1)))
    |> assign(:name, assigns.name || field.name)
    |> assign(:value, assigns.value || field.value)
    |> range_field()
  end

  def range_field(%{appearance: "default"} = assigns) do
    ~H"""
    <div class={[
      width_class(@width),
      @class
    ]}>
      <.label :if={@label} for={@id}>{@label}</.label>
      <div class="relative mb-8">
        <input
          type="range"
          value={@value}
          name={@name}
          id={@id}
          class={["w-full", color_class(@appearance, @color)]}
          {@rest}
        />
        <span
          :for={{range_value, index} <- Enum.with_index(@range_value, 1)}
          id={"#{@id}-value-#{index}"}
          class={[
            "absolute block -bottom-6 text-sm",
            value_position(range_value[:position]),
            range_value[:class]
          ]}
        >
          {render_slot(range_value)}
        </span>
      </div>
      <.error :for={msg <- @errors} icon={@error_icon}>{msg}</.error>
    </div>
    """
  end

  def range_field(assigns) do
    ~H"""
    <div class={[
      color_class(@appearance, @color),
      size_class(@size),
      width_class(@width),
      @class
    ]}>
      <.label :if={@label} for={@id}>{@label}</.label>
      <div class="relative mb-8">
        <input
          type="range"
          value={@value}
          name={@name}
          id={@id}
          class={[
            "range-field bg-transparent cursor-pointer appearance-none disabled:opacity-50",
            "disabled:pointer-events-none focus:outline-hidden",
            "[&::-webkit-slider-runnable-track]:w-full [&::-webkit-slider-thumb]:rounded-full",
            "[&::-webkit-slider-runnable-track]:bg-natural-disabled-light dark:[&::-webkit-slider-runnable-track]:bg-silver-bordered-bg-dark",
            "[&::-webkit-slider-thumb]:bg-natural-disabled-light dark:[&::-webkit-slider-thumb]:bg-silver-bordered-bg-dark",
            "[&::-webkit-slider-thumb]:-mt-0.5 [&::-webkit-slider-thumb]:appearance-none",
            "[&::-webkit-slider-thumb]:transition-all [&::-webkit-slider-thumb]:duration-200 [&::-webkit-slider-thumb]:ease-in-out",
            "[&::-moz-range-thumb]:appearance-none [&::-moz-range-thumb]:bg-white",
            "[&::-moz-range-thumb]:border-4 [&::-moz-range-thumb]:rounded-full",
            "[&::-moz-range-thumb]:transition-all [&::-moz-range-thumb]:duration-200 [&::-moz-range-thumb]:ease-in-out",
            "[&::-webkit-slider-runnable-track]:rounded-full [&::-moz-range-track]:w-full",
            "[&::-moz-range-track]:bg-range-light-gray [&::-moz-range-track]:rounded-full"
          ]}
          {@rest}
        />
        <span
          :for={{range_value, index} <- Enum.with_index(@range_value, 1)}
          id={"#{@id}-value-#{index}"}
          class={[
            "absolute block -bottom-6 text-sm",
            value_position(range_value[:position]),
            range_value[:class]
          ]}
        >
          {render_slot(range_value)}
        </span>
      </div>
      <.error :for={msg <- @errors} icon={@error_icon}>{msg}</.error>
    </div>
    """
  end

  @doc type: :component
  attr :for, :string, default: nil, doc: "Specifies the form which is associated with"
  attr :class, :any, default: nil, doc: "Custom CSS class for additional styling"
  slot :inner_block, required: true, doc: "Inner block that renders HEEx content"

  defp label(assigns) do
    ~H"""
    <label for={@for} class={[display_class("block text-sm font-semibold leading-6", @class), @class]}>
      {render_slot(@inner_block)}
    </label>
    """
  end

  @doc type: :component
  attr :icon, :string, default: nil, doc: "Icon displayed alongside of an item"
  slot :inner_block, required: true, doc: "Inner block that renders HEEx content"

  defp error(assigns) do
    ~H"""
    <p class="mt-3 flex items-center gap-3 text-sm leading-6 text-rose-700">
      <.icon :if={!is_nil(@icon)} name={@icon} class="shrink-0" />
      {render_slot(@inner_block)}
    </p>
    """
  end

  defp value_position(nil), do: value_position("start")
  defp value_position("start"), do: "start-0"
  defp value_position("end"), do: "end-0"
  defp value_position("middle"), do: "start-1/2"
  defp value_position("quarter"), do: "start-1/4"
  defp value_position("three-quarters"), do: "start-3/4"
  defp value_position("two-thirds"), do: "start-2/3 -translate-x-1/2 rtl:translate-x-1/2"
  defp value_position("one-thirds"), do: "start-1/3 -translate-x-1/2 rtl:translate-x-1/2"
  defp value_position(params) when is_binary(params), do: params

  defp width_class("half"), do: "[&_.range-field]:w-1/2"
  defp width_class("full"), do: "[&_.range-field]:w-full"
  defp width_class(params) when is_binary(params), do: params

  defp size_class("extra_small") do
    [
      "[&_.range-field::-webkit-slider-runnable-track]:h-2 [&_.range-field::-webkit-slider-thumb]:size-2.5",
      "[&_.range-field::-moz-range-track]:h-2 [&_.range-field::-moz-range-thumb]:size-2.5"
    ]
  end

  defp size_class("small") do
    [
      "[&_.range-field::-webkit-slider-runnable-track]:h-2.5 [&_.range-field::-webkit-slider-thumb]:size-3",
      "[&_.range-field::-moz-range-track]:h-2.5 [&_.range-field::-moz-range-thumb]:size-3"
    ]
  end

  defp size_class("medium") do
    [
      "[&_.range-field::-webkit-slider-runnable-track]:h-3 [&_.range-field::-webkit-slider-thumb]:size-3.5",
      "[&_.range-field::-moz-range-track]:h-3 [&_.range-field::-moz-range-thumb]:size-3.5"
    ]
  end

  defp size_class("large") do
    [
      "[&_.range-field::-webkit-slider-runnable-track]:h-3.5 [&_.range-field::-webkit-slider-thumb]:size-4",
      "[&_.range-field::-moz-range-track]:h-3.5 [&_.range-field::-moz-range-thumb]:size-4"
    ]
  end

  defp size_class("extra_large") do
    [
      "[&_.range-field::-webkit-slider-runnable-track]:h-4 [&_.range-field::-webkit-slider-thumb]:size-5",
      "[&_.range-field::-moz-range-track]:h-4 [&_.range-field::-moz-range-thumb]:size-5"
    ]
  end

  defp size_class(params) when is_binary(params), do: params

  defp color_class("default", "base") do
    ["accent-base-border-dark dark:accent-base-border-light"]
  end

  defp color_class("default", "white") do
    ["accent-white"]
  end

  defp color_class("default", "natural") do
    ["accent-natural-light dark:accent-natural-dark"]
  end

  defp color_class("default", "primary") do
    ["accent-primary-light dark:accent-primary-dark"]
  end

  defp color_class("default", "secondary") do
    ["accent-secondary-light dark:accent-secondary-dark"]
  end

  defp color_class("default", "success") do
    ["accent-success-light dark:accent-success-dark"]
  end

  defp color_class("default", "warning") do
    ["accent-warning-hover-light dark:accent-warning-dark"]
  end

  defp color_class("default", "danger") do
    ["accent-danger-light dark:accent-danger-dark"]
  end

  defp color_class("default", "info") do
    ["accent-info-light dark:accent-info-dark"]
  end

  defp color_class("default", "silver") do
    ["accent-silver-light dark:accent-silver-dark"]
  end

  defp color_class("default", "dark") do
    ["accent-natural-hover-light"]
  end

  defp color_class("custom", "white") do
    [
      "[&_.range-field::-moz-range-thumb]:border-white",
      "[&_.range-field::-webkit-slider-thumb]:shadow-[0_0_0_4px_var(--color-white)]"
    ]
  end

  defp color_class("custom", "natural") do
    [
      "[&_.range-field::-moz-range-thumb]:border-natural-light",
      "[&_.range-field::-webkit-slider-thumb]:shadow-[0_0_0_4px_var(--color-natural-light)]",
      "dark:[&_.range-field::-moz-range-thumb]:border-natural-dark",
      "dark:[&_.range-field::-webkit-slider-thumb]:shadow-[0_0_0_4px_var(--color-natural-dark)]"
    ]
  end

  defp color_class("custom", "primary") do
    [
      "[&_.range-field::-moz-range-thumb]:border-primary-light",
      "[&_.range-field::-webkit-slider-thumb]:shadow-[0_0_0_4px_var(--color-primary-light)]",
      "dark:[&_.range-field::-moz-range-thumb]:border-primary-dark",
      "dark:[&_.range-field::-webkit-slider-thumb]:shadow-[0_0_0_4px_var(--color-primary-dark)]"
    ]
  end

  defp color_class("custom", "secondary") do
    [
      "[&_.range-field::-moz-range-thumb]:border-secondary-light",
      "[&_.range-field::-webkit-slider-thumb]:shadow-[0_0_0_4px_var(--color-secondary-light)]",
      "dark:[&_.range-field::-moz-range-thumb]:border-secondary-dark",
      "dark:[&_.range-field::-webkit-slider-thumb]:shadow-[0_0_0_4px_var(--color-secondary-dark)]"
    ]
  end

  defp color_class("custom", "success") do
    [
      "[&_.range-field::-moz-range-thumb]:border-success-light",
      "[&_.range-field::-webkit-slider-thumb]:shadow-[0_0_0_4px_var(--color-success-light)]",
      "dark:[&_.range-field::-moz-range-thumb]:border-success-dark",
      "dark:[&_.range-field::-webkit-slider-thumb]:shadow-[0_0_0_4px_var(--color-success-dark)]"
    ]
  end

  defp color_class("custom", "warning") do
    [
      "[&_.range-field::-moz-range-thumb]:border-warning-light",
      "[&_.range-field::-webkit-slider-thumb]:shadow-[0_0_0_4px_var(--color-warning-light)]",
      "dark:[&_.range-field::-moz-range-thumb]:border-warning-dark",
      "dark:[&_.range-field::-webkit-slider-thumb]:shadow-[0_0_0_4px_var(--color-warning-dark)]"
    ]
  end

  defp color_class("custom", "danger") do
    [
      "[&_.range-field::-moz-range-thumb]:border-danger-light",
      "[&_.range-field::-webkit-slider-thumb]:shadow-[0_0_0_4px_var(--color-danger-light)]",
      "dark:[&_.range-field::-moz-range-thumb]:border-danger-dark",
      "dark:[&_.range-field::-webkit-slider-thumb]:shadow-[0_0_0_4px_var(--color-danger-dark)]"
    ]
  end

  defp color_class("custom", "info") do
    [
      "[&_.range-field::-moz-range-thumb]:border-info-light",
      "[&_.range-field::-webkit-slider-thumb]:shadow-[0_0_0_4px_var(--color-info-light)]",
      "dark:[&_.range-field::-moz-range-thumb]:border-info-dark",
      "dark:[&_.range-field::-webkit-slider-thumb]:shadow-[0_0_0_4px_var(--color-info-dark)]"
    ]
  end

  defp color_class("custom", "silver") do
    [
      "[&_.range-field::-moz-range-thumb]:border-silver-light",
      "[&_.range-field::-webkit-slider-thumb]:shadow-[0_0_0_4px_var(--color-silver-light)]",
      "dark:[&_.range-field::-moz-range-thumb]:border-silver-dark",
      "dark:[&_.range-field::-webkit-slider-thumb]:shadow-[0_0_0_4px_var(--color-silver-dark)]"
    ]
  end

  defp color_class("custom", "dark") do
    [
      "[&_.range-field::-moz-range-thumb]:border-natural-hover-light",
      "[&_.range-field::-webkit-slider-thumb]:shadow-[0_0_0_4px_var(--color-natural-hover-light)]"
    ]
  end

  defp color_class(params, _) when is_binary(params), do: params

  defp translate_error({msg, opts}) do
    if count = opts[:count] do
      Gettext.dngettext(BasaWeb.Gettext, "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(BasaWeb.Gettext, "errors", msg, opts)
    end
  end

  defp display_class(default, class) do
    if Enum.any?(class_tokens(class), &display_utility?/1) do
      default |> class_tokens() |> Enum.reject(&display_utility?/1)
    else
      default
    end
  end

  defp display_utility?(token) do
    token in ~w(block inline-block inline flex inline-flex table inline-table table-caption
      table-cell table-column table-column-group table-footer-group table-header-group
      table-row-group table-row flow-root grid inline-grid contents list-item hidden)
  end

  defp class_tokens(class) when is_binary(class), do: String.split(class)
  defp class_tokens(class) when is_list(class), do: Enum.flat_map(class, &class_tokens/1)
  defp class_tokens(_class), do: []
end
