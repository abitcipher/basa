defmodule BasaWeb.Components.Menu do
  use Phoenix.Component
  import BasaWeb.Components.Button, only: [button_link: 1, button: 1]
  import BasaWeb.Components.Collapse, only: [collapse: 1]
  import BasaWeb.Components.Icon, only: [icon: 1]
  import Phoenix.LiveView.Utils, only: [random_id: 0]

  @doc type: :component
  attr :id, :string,
    default: nil,
    doc: "A unique identifier is used to manage state and interaction"

  attr :class, :any, default: nil, doc: "Custom CSS class for additional styling"
  attr :link_class, :string, default: nil, doc: "Custom CSS class for additional styling for link"
  attr :item_class, :string, default: nil, doc: "Custom CSS class for additional styling for li"

  attr :accordion_class, :string,
    default: nil,
    doc: "Custom CSS class for additional styling for accordion"

  attr :menu_items, :list, default: [], doc: "Determines menu items as a list of maps"
  attr :space, :string, default: "small", doc: "Space between items"
  attr :padding, :string, default: "small", doc: "Determines padding for items"

  slot :inner_block,
    doc:
      "Global attributes can define defaults which are merged with attributes provided by the caller"

  attr :rest, :global,
    doc:
      "Global attributes can define defaults which are merged with attributes provided by the caller"

  def menu(assigns) do
    assigns =
      assign(
        assigns,
        :menu_items,
        Enum.map(assigns.menu_items, fn item ->
          Map.put_new_lazy(item, :id, &random_id/0)
        end)
      )

    ~H"""
    <ul
      id={@id}
      class={[
        padding_size(@padding),
        space_class(@space),
        @class
      ]}
      {@rest}
    >
      <li :for={menu_item <- @menu_items} class={@item_class}>
        <.button_link
          :if={Map.get(menu_item, :sub_items, []) == []}
          font_weight={menu_item[:active] && "font-bold"}
          class={@link_class}
          {menu_item}
        />
        <.collapse
          :if={Map.get(menu_item, :sub_items, []) != []}
          id={"#{menu_item[:id]}-collapse"}
          class={@accordion_class}
        >
          <:trigger>
            <.button
              id={menu_item[:id]}
              font_weight={menu_item[:active] && "font-bold"}
              class={@link_class}
              content_position={menu_item[:content_position] || "start"}
              content_class={
                menu_item[:content_class] || "flex justify-between items-center gap-2 w-full"
              }
              display={menu_item[:display] || "flex"}
              full_width={Map.get(menu_item, :full_width, true)}
              {Map.take(menu_item, [:variant, :color, :size, :rounded, :border, :icon, :icon_class, :line_height])}
            >
              {menu_item[:title]}
              <.icon name="hero-chevron-down" class="size-3 transition-transform" />
            </.button>
          </:trigger>
          <.menu
            id={"#{menu_item[:id]}-submenu"}
            class={menu_item[:padding]}
            menu_items={Map.get(menu_item, :sub_items, [])}
          />
        </.collapse>
      </li>
      {render_slot(@inner_block)}
    </ul>
    """
  end

  defp padding_size("extra_small"), do: "p-2"

  defp padding_size("small"), do: "p-2.5"

  defp padding_size("medium"), do: "p-3"

  defp padding_size("large"), do: "p-3.5"

  defp padding_size("extra_large"), do: "p-4"

  defp padding_size("none"), do: "p-0"

  defp padding_size(params) when is_binary(params), do: params

  defp space_class("none"), do: nil

  defp space_class("extra_small"), do: "space-y-2"

  defp space_class("small"), do: "space-y-3"

  defp space_class("medium"), do: "space-y-4"

  defp space_class("large"), do: "space-y-5"

  defp space_class("extra_large"), do: "space-y-6"

  defp space_class(params) when is_binary(params), do: params
end
