defmodule BasaWeb.Components.Indicator do
  use Phoenix.Component

  @indicator_positions [
    "top_left",
    "top_center",
    "top_right",
    "middle_left",
    "middle_right",
    "bottom_left",
    "bottom_center",
    "bottom_right"
  ]

  @doc type: :component
  attr :id, :string,
    default: nil,
    doc: "A unique identifier is used to manage state and interaction"

  attr :size, :string,
    default: "small",
    doc:
      "Determines the overall size of the elements, including padding, font size, and other items"

  attr :class, :any, default: nil, doc: "Custom CSS class for additional styling"
  attr :color, :string, default: "base", doc: "Determines color theme"

  attr :rest, :global,
    include: ["pinging"] ++ @indicator_positions,
    doc:
      "Global attributes can define defaults which are merged with attributes provided by the caller"

  def indicator(%{rest: %{top_left: true}} = assigns) do
    ~H"""
    <span
      id={@id}
      class={[
        indicator_size(@size),
        color_class(@color),
        display_class(
          "indicator block rounded-full absolute -translate-y-1/2 -translate-x-1/2 right-auto top-0 left-0 indicator-top-left",
          @class
        ),
        !is_nil(@rest[:pinging]) && "animate-ping",
        @class
      ]}
      {drop_rest(@rest)}
    />
    """
  end

  def indicator(%{rest: %{top_center: true}} = assigns) do
    ~H"""
    <span
      id={@id}
      class={[
        indicator_size(@size),
        color_class(@color),
        display_class(
          "indicator block rounded-full absolute top-0 -translate-y-1/2 translate-x-1/2 right-1/2",
          @class
        ),
        !is_nil(@rest[:pinging]) && "animate-ping",
        @class
      ]}
      {drop_rest(@rest)}
    />
    """
  end

  def indicator(%{rest: %{top_right: true}} = assigns) do
    ~H"""
    <span
      id={@id}
      class={[
        indicator_size(@size),
        color_class(@color),
        display_class(
          "indicator block rounded-full absolute -translate-y-1/2 translate-x-1/2 left-auto top-0 right-0 indicator-top-right",
          @class
        ),
        !is_nil(@rest[:pinging]) && "animate-ping",
        @class
      ]}
      {drop_rest(@rest)}
    />
    """
  end

  def indicator(%{rest: %{middle_left: true}} = assigns) do
    ~H"""
    <span
      id={@id}
      class={[
        indicator_size(@size),
        color_class(@color),
        display_class(
          "indicator block rounded-full absolute -translate-y-1/2 -translate-x-1/2 right-auto left-0 top-2/4",
          @class
        ),
        !is_nil(@rest[:pinging]) && "animate-ping",
        @class
      ]}
      {drop_rest(@rest)}
    />
    """
  end

  def indicator(%{rest: %{middle_right: true}} = assigns) do
    ~H"""
    <span
      id={@id}
      class={[
        indicator_size(@size),
        color_class(@color),
        display_class(
          "indicator block rounded-full absolute -translate-y-1/2 translate-x-1/2 left-auto right-0 top-2/4",
          @class
        ),
        !is_nil(@rest[:pinging]) && "animate-ping",
        @class
      ]}
      {drop_rest(@rest)}
    />
    """
  end

  def indicator(%{rest: %{bottom_left: true}} = assigns) do
    ~H"""
    <span
      id={@id}
      class={[
        indicator_size(@size),
        color_class(@color),
        display_class(
          "indicator block rounded-full absolute translate-y-1/2 -translate-x-1/2 right-auto bottom-0 left-0 indicator-bottom-left",
          @class
        ),
        !is_nil(@rest[:pinging]) && "animate-ping",
        @class
      ]}
      {drop_rest(@rest)}
    />
    """
  end

  def indicator(%{rest: %{bottom_center: true}} = assigns) do
    ~H"""
    <span
      id={@id}
      class={[
        indicator_size(@size),
        color_class(@color),
        display_class(
          "indicator block rounded-full absolute translate-y-1/2 translate-x-1/2 bottom-0 right-1/2",
          @class
        ),
        !is_nil(@rest[:pinging]) && "animate-ping",
        @class
      ]}
      {drop_rest(@rest)}
    />
    """
  end

  def indicator(%{rest: %{bottom_right: true}} = assigns) do
    ~H"""
    <span
      id={@id}
      class={[
        indicator_size(@size),
        color_class(@color),
        display_class(
          "indicator block rounded-full absolute translate-y-1/2 translate-x-1/2 left-auto bottom-0 right-0 indicator-bottom-right",
          @class
        ),
        !is_nil(@rest[:pinging]) && "animate-ping",
        @class
      ]}
      {drop_rest(@rest)}
    />
    """
  end

  def indicator(assigns) do
    ~H"""
    <span
      id={@id}
      class={[
        indicator_size(@size),
        color_class(@color),
        display_class("block indicator rounded-full", @class),
        !is_nil(@rest[:pinging]) && "animate-ping",
        @class
      ]}
      {drop_rest(@rest)}
    />
    """
  end

  defp indicator_size("extra_small"), do: "size-2!"

  defp indicator_size("small"), do: "size-2.5!"

  defp indicator_size("medium"), do: "size-3!"

  defp indicator_size("large"), do: "size-3.5!"

  defp indicator_size("extra_large"), do: "size-4!"

  defp indicator_size(params) when is_binary(params), do: params

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

  defp drop_rest(rest) do
    all_rest =
      (["pinging"] ++ @indicator_positions)
      |> Enum.map(&if(is_binary(&1), do: String.to_atom(&1), else: &1))

    Map.drop(rest, all_rest)
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
