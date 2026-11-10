defmodule BasaWeb.Components.Breadcrumb do
  use Phoenix.Component
  import BasaWeb.Components.Icon, only: [icon: 1]

  @doc type: :component
  attr :class, :any, default: nil, doc: "Custom CSS class for additional styling"
  attr :items_wrapper_class, :string, default: nil, doc: "Custom CSS class for additional styling"

  attr :id, :string,
    default: nil,
    doc: "A unique identifier is used to manage state and interaction"

  attr :separator_icon, :string,
    default: "hero-chevron-right",
    doc: "Determines a separator for items of an element"

  attr :separator_icon_class, :string,
    default: "rtl:rotate-180",
    doc: "Custom CSS class for additional styling"

  attr :separator_text, :string,
    default: nil,
    doc: "Determines a separator for items of an element"

  attr :separator_text_class, :string,
    default: nil,
    doc: "Determines a separator for items of an element"

  attr :color, :string, default: "base", doc: "Determines color theme"

  attr :size, :string,
    default: "small",
    doc:
      "Determines the overall size of the elements, including padding, font size, and other items"

  slot :item, required: false, doc: "Specifies item slot of a breadcrumb" do
    attr :icon, :string, doc: "Icon displayed alongside of an item"
    attr :link, :string, doc: "Renders a navigation, patch link or normal link"
    attr :title, :string, doc: "Renders a navigation, patch link or normal link"
    attr :class, :any, doc: "Custom CSS class for additional styling"
    attr :icon_class, :string, doc: "Custom CSS class for additional styling"
    attr :link_class, :string, doc: "Custom CSS class for additional styling"
  end

  attr :rest, :global,
    doc:
      "Global attributes can define defaults which are merged with attributes provided by the caller"

  slot :inner_block, required: false, doc: "Inner block that renders HEEx content"

  def breadcrumb(assigns) do
    ~H"""
    <nav class={@class} id={@id} {@rest}>
      <ol class={[default_classes(), color_class(@color), size_class(@size), @items_wrapper_class]}>
        <li
          :for={{item, index} <- Enum.with_index(@item, 1)}
          class={["flex items-center", item[:class]]}
        >
          <.icon
            :if={!is_nil(item[:icon])}
            name={item[:icon]}
            class={["breadcrumb-icon shrink-0", item[:icon_class]]}
          />
          <.link
            :if={!is_nil(item[:link])}
            navigate={item[:link]}
            title={item[:title]}
            class={item[:link_class]}
          >{render_slot(item)}</.link>

          <div :if={is_nil(item[:link])}>{render_slot(item)}</div>

          <.icon
            :if={@separator_icon && index < Enum.count(@item)}
            name={@separator_icon}
            class={["separator-icon shrink-0", @separator_icon_class]}
          />
          <span
            :if={@separator_text && !@separator_icon && index < Enum.count(@item)}
            class={["separator-text shrink-0", @separator_text_class]}
          >
            {@separator_text}
          </span>
        </li>
        {render_slot(@inner_block)}
      </ol>
    </nav>
    """
  end

  defp color_class("base") do
    [
      "text-base-text-light [&>li_a]:hover:text-base-text-hover-light",
      "dark:text-base-text-dark dark:[&>li_a]:hover:text-base-text-hover-dark"
    ]
  end

  defp color_class("white") do
    [
      "text-white [&>li_a]:hover:text-natural-disabled-light"
    ]
  end

  defp color_class("dark") do
    [
      "text-bordered-dark-bg [&>li_a]:hover:text-natural-disabled-dark"
    ]
  end

  defp color_class("natural") do
    [
      "text-natural-light [&>li_a]:hover:text-natural-hover-light",
      "dark:text-natural-dark dark:[&>li_a]:hover:text-natural-hover-dark"
    ]
  end

  defp color_class("primary") do
    [
      "text-primary-light [&>li_a]:hover:text-primary-hover-light",
      "dark:text-primary-dark dark:[&>li_a]:hover:text-primary-hover-dark"
    ]
  end

  defp color_class("secondary") do
    [
      "text-secondary-light [&>li_a]:hover:text-secondary-hover-light",
      "dark:text-secondary-dark dark:[&>li_a]:hover:text-secondary-hover-dark"
    ]
  end

  defp color_class("success") do
    [
      "text-success-light [&>li_a]:hover:text-success-hover-light",
      "dark:text-success-dark dark:[&>li_a]:hover:text-success-hover-dark"
    ]
  end

  defp color_class("warning") do
    [
      "text-warning-light [&>li_a]:hover:text-warning-hover-light",
      "dark:text-warning-dark dark:[&>li_a]:hover:text-warning-hover-dark"
    ]
  end

  defp color_class("danger") do
    [
      "text-danger-light [&>li_a]:hover:text-danger-hover-light",
      "dark:text-danger-dark dark:[&>li_a]:hover:text-danger-hover-dark"
    ]
  end

  defp color_class("info") do
    [
      "text-info-light [&>li_a]:hover:text-info-hover-light",
      "dark:text-info-dark dark:[&>li_a]:hover:text-info-hover-dark"
    ]
  end

  defp color_class("silver") do
    [
      "text-silver-light [&>li_a]:hover:text-silver-hover-light",
      "dark:text-silver-dark dark:[&>li_a]:hover:text-silver-hover-dark"
    ]
  end

  defp color_class(params) when is_binary(params), do: params

  defp size_class("extra_small") do
    "text-xs gap-1.5 [&>li]:gap-1.5 [&>li>.separator-icon]:size-3 [&>li>.breadcrumb-icon]:size-4"
  end

  defp size_class("small") do
    "text-sm gap-2 [&>li]:gap-2 [&>li>.separator-icon]:size-3.5 [&>li>.breadcrumb-icon]:size-5"
  end

  defp size_class("medium") do
    "text-base gap-2.5 [&>li]:gap-2.5 [&>li>.separator-icon]:size-4 [&>li>.breadcrumb-icon]:size-6"
  end

  defp size_class("large") do
    "text-lg gap-3 [&>li]:gap-3 [&>li>.separator-icon]:size-5 [&>li>.breadcrumb-icon]:size-7"
  end

  defp size_class("extra_large") do
    "text-xl gap-3.5 [&>li]:gap-3.5 [&>li>.separator-icon]:size-6 [&>li>.breadcrumb-icon]:size-8"
  end

  defp size_class(params) when is_binary(params), do: params

  defp default_classes do
    [
      "flex flex-wrap items-center transition-all ease-in-out duration-100 group"
    ]
  end
end
