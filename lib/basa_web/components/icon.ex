defmodule BasaWeb.Components.Icon do
  use Phoenix.Component

  @doc type: :component
  attr :name, :string, required: true
  attr :class, :any, default: nil

  attr :rest, :global,
    doc:
      "Global attributes can define defaults which are merged with attributes provided by the caller"

  def icon(%{name: "hero-" <> _} = assigns) do
    ~H"""
    <span class={[@name, @class]} {@rest} />
    """
  end
end
