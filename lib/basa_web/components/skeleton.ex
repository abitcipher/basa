defmodule BasaWeb.Components.Skeleton do
  use Phoenix.Component
  use Gettext, backend: BasaWeb.Gettext

  @doc type: :component
  attr :id, :string,
    default: nil,
    doc: "A unique identifier is used to manage state and interaction"

  attr :class, :any, default: nil, doc: "Custom CSS class for additional styling"
  attr :color, :string, default: "base", doc: "Determines color theme"
  attr :height, :string, default: "extra_small", doc: "Determines the element height"
  attr :width, :string, default: "full", doc: "Determines the element width"
  attr :rounded, :string, default: "small", doc: "Determines the border radius"

  attr :visible, :boolean,
    default: true,
    doc: "Controls whether the skeleton is visible or hidden"

  attr :rest, :global,
    include: ~w(animated),
    doc:
      "Global attributes can define defaults which are merged with attributes provided by the caller"

  def skeleton(assigns) do
    ~H"""
    <div
      :if={@visible}
      role="status"
      aria-live="polite"
      aria-busy="true"
      id={@id}
      class={[
        rounded_size(@rounded),
        width_class(@width),
        height_class(@height),
        color_class(@color),
        @rest[:animated] && "animate-pulse",
        @class
      ]}
      {@rest}
    >
      <span class="sr-only">{gettext("Loading...")}</span>
    </div>
    """
  end

  defp rounded_size("extra_small"), do: "rounded-xs"

  defp rounded_size("small"), do: "rounded-sm"

  defp rounded_size("medium"), do: "rounded-md"

  defp rounded_size("large"), do: "rounded-lg"

  defp rounded_size("extra_large"), do: "rounded-xl"

  defp rounded_size("full"), do: "rounded-full"

  defp rounded_size("none"), do: "rounded-none"

  defp rounded_size(params) when is_binary(params), do: params

  defp height_class("extra_small"), do: "h-1"
  defp height_class("small"), do: "h-2"
  defp height_class("medium"), do: "h-3"
  defp height_class("large"), do: "h-4"
  defp height_class("extra_large"), do: "h-5"
  defp height_class(params) when is_binary(params), do: params

  defp width_class("extra_small"), do: "w-60"
  defp width_class("small"), do: "w-64"
  defp width_class("medium"), do: "w-72"
  defp width_class("large"), do: "w-80"
  defp width_class("extra_large"), do: "w-96"
  defp width_class("full"), do: "w-full"
  defp width_class(params) when is_binary(params), do: params

  defp color_class("base"), do: "bg-base-border-light dark:bg-base-border-dark"

  defp color_class("white"), do: "bg-white"

  defp color_class("natural"), do: "bg-natural-light dark:bg-natural-dark"

  defp color_class("primary"), do: "bg-primary-light dark:bg-primary-dark"

  defp color_class("secondary"), do: "bg-secondary-light dark:bg-secondary-dark"

  defp color_class("success"), do: "bg-success-light dark:bg-success-dark"

  defp color_class("warning"), do: "bg-warning-light dark:bg-warning-dark"

  defp color_class("danger"), do: "bg-danger-light dark:bg-danger-dark"

  defp color_class("info"), do: "bg-info-light dark:bg-info-dark"

  defp color_class("silver"), do: "bg-silver-light dark:bg-silver-dark"

  defp color_class("dark"), do: "bg-default-dark-bg"

  defp color_class(params) when is_binary(params), do: params
end
