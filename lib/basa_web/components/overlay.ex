defmodule BasaWeb.Components.Overlay do
  use Phoenix.Component

  @doc type: :component
  attr :id, :string,
    default: nil,
    doc: "A unique identifier is used to manage state and interaction"

  attr :color, :string, default: "base", doc: "Determines color theme"
  attr :opacity, :string, default: "", doc: "Determines the opacity level of the overlay"
  attr :backdrop, :string, default: "", doc: "Determines backdrop effects for the overlay"
  attr :class, :any, default: nil, doc: "Custom CSS class for additional styling"

  attr :z_index, :string,
    default: "z-50",
    doc:
      "Utility class for controlling the z-index stacking order of the overlay (e.g., 'z-10', 'z-50')."

  attr :rest, :global,
    doc:
      "Global attributes can define defaults which are merged with attributes provided by the caller"

  slot :inner_block, required: false, doc: "Inner block that renders HEEx content"

  @spec overlay(map()) :: Phoenix.LiveView.Rendered.t()
  def overlay(assigns) do
    ~H"""
    <div
      id={@id}
      data-opacity={@opacity}
      aria-hidden="true"
      role="presentation"
      tabindex="-1"
      class={[
        "overlay absolute inset-0",
        color_class(@color),
        backdrop_class(@backdrop),
        @z_index,
        @class
      ]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </div>
    """
  end

  defp color_class("base") do
    ["bg-white/[var(--overlay-opacity)] dark:bg-base-bg-dark/[var(--overlay-opacity)]"]
  end

  defp color_class("white") do
    ["bg-white/[var(--overlay-opacity)] text-black"]
  end

  defp color_class("dark") do
    ["bg-default-dark-bg/[var(--overlay-opacity)] text-white"]
  end

  defp color_class("natural") do
    ["bg-natural-light/[var(--overlay-opacity)] dark:bg-natural-dark/[var(--overlay-opacity)]"]
  end

  defp color_class("primary") do
    ["bg-primary-light/[var(--overlay-opacity)] dark:bg-primary-dark/[var(--overlay-opacity)]"]
  end

  defp color_class("secondary") do
    [
      "bg-secondary-light/[var(--overlay-opacity)] dark:bg-secondary-dark/[var(--overlay-opacity)]"
    ]
  end

  defp color_class("success") do
    ["bg-success-light/[var(--overlay-opacity)] dark:bg-success-dark/[var(--overlay-opacity)]"]
  end

  defp color_class("warning") do
    ["bg-warning-light/[var(--overlay-opacity)] dark:bg-warning-dark/[var(--overlay-opacity)]"]
  end

  defp color_class("danger") do
    ["bg-danger-light/[var(--overlay-opacity)] dark:bg-danger-dark/[var(--overlay-opacity)]"]
  end

  defp color_class("info") do
    ["bg-info-light/[var(--overlay-opacity)] dark:bg-info-dark/[var(--overlay-opacity)]"]
  end

  defp color_class("silver") do
    ["bg-silver-light/[var(--overlay-opacity)] dark:bg-silver-dark/[var(--overlay-opacity)]"]
  end

  defp color_class(params) when is_binary(params), do: params

  defp backdrop_class("extra_small") do
    "backdrop-blur-[1px]"
  end

  defp backdrop_class("small") do
    "backdrop-blur-[2px]"
  end

  defp backdrop_class("medium") do
    "backdrop-blur-[3px]"
  end

  defp backdrop_class("large") do
    "backdrop-blur-[4px]"
  end

  defp backdrop_class("extra_large") do
    "backdrop-blur-[5px]"
  end

  defp backdrop_class(params) when is_binary(params), do: params
end
