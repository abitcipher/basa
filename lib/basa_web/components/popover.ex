defmodule BasaWeb.Components.Popover do
  use Phoenix.Component
  alias Phoenix.LiveView.JS
  import Phoenix.LiveView.Utils, only: [random_id: 0]

  @doc type: :component
  attr :id, :string,
    required: true,
    doc: "A unique identifier is used to manage state and interaction"

  attr :class, :any, default: nil, doc: "Custom CSS class for additional styling"
  attr :inline, :boolean, default: false, doc: "Determines whether this element is inline"

  attr :clickable, :boolean,
    default: false,
    doc: "Determines if the element can be activated on click"

  attr :position, :string, default: "top", doc: "Determines the element position"
  attr :show_delay, :integer, default: 0, doc: "Delay before showing (ms)"
  attr :hide_delay, :integer, default: 200, doc: "Delay before hiding (ms)"
  attr :variant, :string, default: "base", doc: "Determines the style"
  attr :color, :string, default: "natural", doc: "Determines color theme"
  attr :rounded, :string, default: "medium", doc: "Determines the border radius"
  attr :show_arrow, :boolean, default: true, doc: "Show or hide arrow of popover"
  attr :border, :string, default: "extra_small", doc: "Determines border style"
  attr :size, :string, default: "small", doc: "Determines the overall size of the elements"
  attr :space, :string, default: "", doc: "Space between items"
  attr :width, :string, default: "fit", doc: "Determines the element width"
  attr :text_position, :string, default: "start", doc: "Determines the element's text position"

  attr :font_weight, :string,
    default: "font-normal",
    doc: "Determines custom class for the font weight"

  attr :padding, :string, default: "small", doc: "Determines padding for items"
  attr :content_class, :string, default: "", doc: "Additional CSS classes for popover content"
  attr :trigger_class, :string, default: "", doc: "Additional CSS classes for popover content"
  attr :arrow_class, :string, default: "", doc: "Additional CSS classes for arrow"
  attr :rest, :global, doc: "Global attributes"

  slot :inner_block, required: false, doc: "Inner block that renders HEEx content"

  slot :content, required: false do
    attr :class, :any, doc: "Custom CSS class for additional styling"
  end

  slot :trigger, required: false do
    attr :class, :any, doc: "Custom CSS class for additional styling"
  end

  def popover(assigns) do
    assigns =
      assigns
      |> assign_new(:id, fn -> "popover-#{random_id()}" end)

    ~H"""
    <span
      :if={@inline}
      id={@id}
      phx-hook="Floating"
      data-pb-open={JS.dispatch("chelekom:open", to: "##{@id}")}
      data-pb-close={JS.dispatch("chelekom:close", to: "##{@id}")}
      data-pb-toggle={JS.dispatch("chelekom:toggle", to: "##{@id}")}
      data-position={@position}
      data-smart-position="false"
      data-clickable={to_string(@clickable)}
      data-show-delay={@show_delay}
      data-hide-delay={@hide_delay}
      data-enable-aria="true"
      data-floating-type="popover"
      class={@class}
      {@rest}
    >
      <span
        data-floating-trigger
        class={[@clickable && "cursor-pointer [&_button]:cursor-pointer", @trigger_class]}
      >
        <span :for={trigger <- @trigger} :if={@trigger != []} class={trigger[:class]}>
          {render_slot(trigger)}
        </span>
        <span :if={@trigger == [] && @inner_block != []}>
          {render_slot(@inner_block)}
        </span>
      </span>

      <span
        id={"#{@id}-content"}
        role="dialog"
        data-floating-content
        aria-hidden="true"
        tabindex="0"
        hidden
        class={[
          "absolute z-50 transition-all ease-in-out duration-200",
          color_variant(@variant, @color),
          rounded_size(@rounded),
          size_class(@size),
          wrapper_padding(@padding),
          border_class(@border, @variant),
          text_position(@text_position),
          width_class(@width),
          space_class(@space),
          @font_weight,
          @content_class
        ]}
      >
        <span
          :if={@show_arrow && @variant not in ~w(bordered base)}
          class={[
            "absolute w-2 h-2 bg-inherit rotate-45 -z-10",
            arrow_position_class(@position),
            @arrow_class
          ]}
        ></span>

        <span :for={content <- @content} :if={@content != []} class={content[:class]}>
          {render_slot(content)}
        </span>
      </span>
    </span>

    <div
      :if={!@inline}
      id={@id}
      phx-hook="Floating"
      data-pb-open={JS.dispatch("chelekom:open", to: "##{@id}")}
      data-pb-close={JS.dispatch("chelekom:close", to: "##{@id}")}
      data-pb-toggle={JS.dispatch("chelekom:toggle", to: "##{@id}")}
      data-position={@position}
      data-smart-position="false"
      data-clickable={to_string(@clickable)}
      data-show-delay={@show_delay}
      data-hide-delay={@hide_delay}
      data-enable-aria="true"
      data-floating-type="popover"
      class={@class}
      {@rest}
    >
      <div
        data-floating-trigger
        class={[@clickable && "cursor-pointer [&_button]:cursor-pointer", @trigger_class]}
      >
        <span :for={trigger <- @trigger} :if={@trigger != []} class={trigger[:class]}>
          {render_slot(trigger)}
        </span>
        <span :if={@trigger == [] && @inner_block != []}>
          {render_slot(@inner_block)}
        </span>
      </div>

      <div
        id={"#{@id}-content"}
        role="dialog"
        data-floating-content
        aria-hidden="true"
        tabindex="0"
        hidden
        class={[
          "absolute z-50 transition-all ease-in-out duration-200",
          color_variant(@variant, @color),
          rounded_size(@rounded),
          size_class(@size),
          wrapper_padding(@padding),
          border_class(@border, @variant),
          text_position(@text_position),
          width_class(@width),
          space_class(@space),
          @font_weight,
          @content_class
        ]}
      >
        <span
          :if={@show_arrow && @variant not in ~w(bordered base)}
          class={[
            "absolute w-2 h-2 bg-inherit rotate-45 -z-10",
            arrow_position_class(@position),
            @arrow_class
          ]}
        ></span>

        <span :for={content <- @content} :if={@content != []} class={content[:class]}>
          {render_slot(content)}
        </span>
      </div>
    </div>
    """
  end

  defp arrow_position_class("top"), do: "bottom-[-4px] left-1/2 -translate-x-1/2"
  defp arrow_position_class("bottom"), do: "top-[-4px] left-1/2 -translate-x-1/2"
  defp arrow_position_class("left"), do: "right-[-4px] top-1/2 -translate-y-1/2"
  defp arrow_position_class("right"), do: "left-[-4px] top-1/2 -translate-y-1/2"
  defp arrow_position_class(_), do: arrow_position_class("top")

  defp border_class(_, variant) when variant in ["default", "shadow", "gradient"],
    do: nil

  defp border_class("extra_small", _), do: "border"
  defp border_class("small", _), do: "border-2"
  defp border_class("medium", _), do: "border-[3px]"
  defp border_class("large", _), do: "border-4"
  defp border_class("extra_large", _), do: "border-[5px]"
  defp border_class("none", _), do: nil
  defp border_class(params, _) when is_binary(params), do: params

  defp rounded_size("extra_small"), do: "rounded-xs"

  defp rounded_size("small"), do: "rounded-sm"

  defp rounded_size("medium"), do: "rounded-md"

  defp rounded_size("large"), do: "rounded-lg"

  defp rounded_size("extra_large"), do: "rounded-xl"

  defp rounded_size("none"), do: "rounded-none"

  defp rounded_size(params) when is_binary(params), do: params

  defp size_class("extra_small"), do: "text-xs max-w-60"

  defp size_class("small"), do: "text-sm max-w-64.5"

  defp size_class("medium"), do: "text-base max-w-72"

  defp size_class("large"), do: "text-lg max-w-80"

  defp size_class("extra_large"), do: "text-xl max-w-96"

  defp size_class(params) when is_binary(params), do: params

  defp text_position("left"), do: "text-left"
  defp text_position("right"), do: "text-right"
  defp text_position("center"), do: "text-center"
  defp text_position("justify"), do: "text-justify"
  defp text_position("start"), do: "text-start"
  defp text_position("end"), do: "text-end"
  defp text_position(params) when is_binary(params), do: params

  defp width_class("extra_small"), do: "min-w-48"
  defp width_class("small"), do: "min-w-52"
  defp width_class("medium"), do: "min-w-56"
  defp width_class("large"), do: "min-w-60"
  defp width_class("extra_large"), do: "min-w-64"
  defp width_class("double_large"), do: "min-w-72"
  defp width_class("triple_large"), do: "min-w-80"
  defp width_class("quadruple_large"), do: "min-w-96"
  defp width_class(params) when is_binary(params), do: params

  defp wrapper_padding("extra_small"), do: "p-1"

  defp wrapper_padding("small"), do: "p-2"

  defp wrapper_padding("medium"), do: "p-3"

  defp wrapper_padding("large"), do: "p-4"

  defp wrapper_padding("extra_large"), do: "p-5"

  defp wrapper_padding("none"), do: nil
  defp wrapper_padding(params) when is_binary(params), do: params

  defp space_class("extra_small"), do: "space-y-2"

  defp space_class("small"), do: "space-y-3"

  defp space_class("medium"), do: "space-y-4"

  defp space_class("large"), do: "space-y-5"

  defp space_class("extra_large"), do: "space-y-6"

  defp space_class(params) when is_binary(params), do: params

  defp color_variant("base", _) do
    [
      "bg-white text-base-text-light border-base-border-light shadow-xs",
      "dark:bg-base-bg-dark dark:text-base-text-dark dark:border-base-border-dark"
    ]
  end

  defp color_variant("default", "white") do
    ["bg-white text-black"]
  end

  defp color_variant("default", "dark") do
    ["bg-default-dark-bg text-white"]
  end

  defp color_variant("default", "natural") do
    [
      "bg-natural-light text-white dark:bg-natural-dark dark:text-black"
    ]
  end

  defp color_variant("default", "primary") do
    [
      "bg-primary-light text-white dark:bg-primary-dark dark:text-black"
    ]
  end

  defp color_variant("default", "secondary") do
    [
      "bg-secondary-light text-white dark:bg-secondary-dark dark:text-black"
    ]
  end

  defp color_variant("default", "success") do
    [
      "bg-success-light text-white dark:bg-success-dark dark:text-black"
    ]
  end

  defp color_variant("default", "warning") do
    [
      "bg-warning-light text-white dark:bg-warning-dark dark:text-black"
    ]
  end

  defp color_variant("default", "danger") do
    [
      "bg-danger-light text-white dark:bg-danger-dark dark:text-black"
    ]
  end

  defp color_variant("default", "info") do
    [
      "bg-info-light text-white dark:bg-info-dark dark:text-black"
    ]
  end

  defp color_variant("default", "silver") do
    [
      "bg-silver-light text-white dark:bg-silver-dark dark:text-black"
    ]
  end

  defp color_variant("shadow", "natural") do
    [
      "bg-natural-light text-white dark:bg-natural-dark dark:text-black",
      "shadow-[0px_4px_6px_-4px_var(--color-shadow-natural)] shadow-[0px_10px_15px_-3px_var(--color-shadow-natural)] dark:shadow-none"
    ]
  end

  defp color_variant("shadow", "primary") do
    [
      "bg-primary-light text-white dark:bg-primary-dark dark:text-black",
      "shadow-[0px_4px_6px_-4px_var(--color-shadow-primary)] shadow-[0px_10px_15px_-3px_var(--color-shadow-primary)] dark:shadow-none"
    ]
  end

  defp color_variant("shadow", "secondary") do
    [
      "bg-secondary-light text-white dark:bg-secondary-dark dark:text-black",
      "shadow-[0px_4px_6px_-4px_var(--color-shadow-secondary)] shadow-[0px_10px_15px_-3px_var(--color-shadow-secondary)] dark:shadow-none"
    ]
  end

  defp color_variant("shadow", "success") do
    [
      "bg-success-light text-white dark:bg-success-dark dark:text-black",
      "shadow-[0px_4px_6px_-4px_var(--color-shadow-success)] shadow-[0px_10px_15px_-3px_var(--color-shadow-success)] dark:shadow-none"
    ]
  end

  defp color_variant("shadow", "warning") do
    [
      "bg-warning-light text-white dark:bg-warning-dark dark:text-black",
      "shadow-[0px_4px_6px_-4px_var(--color-shadow-warning)] shadow-[0px_10px_15px_-3px_var(--color-shadow-warning)] dark:shadow-none"
    ]
  end

  defp color_variant("shadow", "danger") do
    [
      "bg-danger-light text-white dark:bg-danger-dark dark:text-black",
      "shadow-[0px_4px_6px_-4px_var(--color-shadow-danger)] shadow-[0px_10px_15px_-3px_var(--color-shadow-danger)] dark:shadow-none"
    ]
  end

  defp color_variant("shadow", "info") do
    [
      "bg-info-light text-white dark:bg-info-dark dark:text-black",
      "shadow-[0px_4px_6px_-4px_var(--color-shadow-info)] shadow-[0px_10px_15px_-3px_var(--color-shadow-info)] dark:shadow-none"
    ]
  end

  defp color_variant("shadow", "silver") do
    [
      "bg-silver-light text-white dark:bg-silver-dark dark:text-black",
      "shadow-[0px_4px_6px_-4px_var(--color-shadow-silver)] shadow-[0px_10px_15px_-3px_var(--color-shadow-silver)] dark:shadow-none"
    ]
  end

  defp color_variant("bordered", "white") do
    [
      "bg-white text-black border-natural-dark"
    ]
  end

  defp color_variant("bordered", "dark") do
    [
      "bg-default-dark-bg text-white border-silver-hover-light"
    ]
  end

  defp color_variant("bordered", "natural") do
    [
      "text-natural-bordered-text-light border-natural-bordered-text-light bg-natural-bordered-bg-light",
      "dark:text-natural-bordered-text-dark dark:border-natural-bordered-text-dark dark:bg-natural-bordered-bg-dark"
    ]
  end

  defp color_variant("bordered", "primary") do
    [
      "text-primary-bordered-text-light border-primary-bordered-text-light bg-primary-bordered-bg-light",
      "dark:text-primary-bordered-text-dark dark:border-primary-bordered-text-dark dark:bg-primary-bordered-bg-dark"
    ]
  end

  defp color_variant("bordered", "secondary") do
    [
      "text-secondary-bordered-text-light border-secondary-bordered-text-light bg-secondary-bordered-bg-light",
      "dark:text-secondary-bordered-text-dark dark:border-secondary-bordered-text-dark dark:bg-secondary-bordered-bg-dark"
    ]
  end

  defp color_variant("bordered", "success") do
    [
      "text-success-bordered-text-light border-success-bordered-text-light bg-success-bordered-bg-light",
      "dark:text-success-bordered-text-dark dark:border-success-bordered-text-dark dark:bg-success-bordered-bg-dark"
    ]
  end

  defp color_variant("bordered", "warning") do
    [
      "text-warning-bordered-text-light border-warning-bordered-text-light bg-warning-bordered-bg-light",
      "dark:text-warning-bordered-text-dark dark:border-warning-bordered-text-dark dark:bg-warning-bordered-bg-dark"
    ]
  end

  defp color_variant("bordered", "danger") do
    [
      "text-danger-bordered-text-light border-danger-bordered-text-light bg-danger-bordered-bg-light",
      "dark:text-danger-bordered-text-dark dark:border-danger-bordered-text-dark dark:bg-danger-bordered-bg-dark"
    ]
  end

  defp color_variant("bordered", "info") do
    [
      "text-info-bordered-text-light border-info-bordered-text-light bg-info-bordered-bg-light",
      "dark:text-info-bordered-text-dark dark:border-info-bordered-text-dark dark:bg-info-bordered-bg-dark"
    ]
  end

  defp color_variant("bordered", "silver") do
    [
      "text-silver-bordered-text-light border-silver-bordered-text-light bg-silver-bordered-bg-light",
      "dark:text-silver-bordered-text-dark dark:border-silver-bordered-text-dark dark:bg-silver-bordered-bg-dark"
    ]
  end

  defp color_variant("gradient", "natural") do
    [
      "bg-linear-to-br from-gradient-natural-from-light to-gradient-natural-to-light text-white",
      "dark:from-gradient-natural-from-dark dark:to-white dark:text-black"
    ]
  end

  defp color_variant("gradient", "primary") do
    [
      "bg-linear-to-br from-gradient-primary-from-light to-gradient-primary-to-light text-white",
      "dark:from-gradient-primary-from-dark dark:to-gradient-primary-to-dark dark:text-black"
    ]
  end

  defp color_variant("gradient", "secondary") do
    [
      "bg-linear-to-br from-gradient-secondary-from-light to-gradient-secondary-to-light text-white",
      "dark:from-gradient-secondary-from-dark dark:to-gradient-secondary-to-dark dark:text-black"
    ]
  end

  defp color_variant("gradient", "success") do
    [
      "bg-linear-to-br from-gradient-success-from-light to-gradient-success-to-light text-white",
      "dark:from-gradient-success-from-dark dark:to-gradient-success-to-dark dark:text-black"
    ]
  end

  defp color_variant("gradient", "warning") do
    [
      "bg-linear-to-br from-gradient-warning-from-light to-gradient-warning-to-light text-white",
      "dark:from-gradient-warning-from-dark dark:to-gradient-warning-to-dark dark:text-black"
    ]
  end

  defp color_variant("gradient", "danger") do
    [
      "bg-linear-to-br from-gradient-danger-from-light to-gradient-danger-to-light text-white",
      "dark:from-gradient-danger-from-dark dark:to-gradient-danger-to-dark dark:text-black"
    ]
  end

  defp color_variant("gradient", "info") do
    [
      "bg-linear-to-br from-gradient-info-from-light to-gradient-info-to-light text-white",
      "dark:from-gradient-info-from-dark dark:to-gradient-info-to-dark dark:text-black"
    ]
  end

  defp color_variant("gradient", "silver") do
    [
      "bg-linear-to-br from-gradient-silver-from-light to-gradient-silver-to-light text-white",
      "dark:from-gradient-silver-from-dark dark:to-gradient-silver-to-dark dark:text-black"
    ]
  end

  defp color_variant(params, _) when is_binary(params), do: params
end
