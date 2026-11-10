defmodule BasaWeb.Components.Collapse do
  use Phoenix.Component
  alias Phoenix.LiveView.JS

  @doc type: :component
  attr :id, :string, required: true, doc: "A unique identifier for the collapse"
  attr :class, :any, default: nil, doc: "Custom CSS class for additional styling"
  attr :duration, :integer, default: 200, doc: "Animation duration in milliseconds"
  attr :keep_mounted, :boolean, default: false, doc: "Keep content mounted after first open"
  attr :server_events, :boolean, default: false, doc: "Send open/close events to LiveView"
  attr :event_handler, :string, default: nil, doc: "Specify event handler for collapse events"
  attr :open, :boolean, default: false, doc: "Whether the collapse is initially open"

  slot :trigger, required: true, doc: "The clickable trigger element"
  slot :inner_block, required: true, doc: "The collapsible content"

  def collapse(assigns) do
    assigns = assigns |> assign(:item_id, "#{assigns.id}-item")

    ~H"""
    <div
      id={@id}
      phx-hook="Collapsible"
      data-pb-open={JS.dispatch("chelekom:open", to: "##{@id}")}
      data-pb-close={JS.dispatch("chelekom:close", to: "##{@id}")}
      data-pb-toggle={JS.dispatch("chelekom:toggle", to: "##{@id}")}
      data-multiple="false"
      data-collapsible="true"
      data-duration={@duration}
      data-keep-mounted={to_string(@keep_mounted)}
      data-server-events={to_string(@server_events)}
      data-event-handler={@event_handler}
      data-initial-open={if @open, do: @item_id, else: ""}
      class={@class}
    >
      <div class="collapse-item">
        <div
          data-collapsible-trigger={@item_id}
          class="collapse-trigger cursor-pointer [&_button]:cursor-pointer"
        >
          {render_slot(@trigger)}
        </div>

        <div data-collapsible-panel={@item_id} class="collapse-panel">
          <div
            data-collapsible-content
            class="transition-[max-height] max-h-0"
            data-duration={@duration}
          >
            <div class="collapse-content">{render_slot(@inner_block)}</div>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
