defmodule BasaWeb.Components.Clipboard do
  use Phoenix.Component
  use Gettext, backend: BasaWeb.Gettext
  import Phoenix.LiveView.Utils, only: [random_id: 0]

  @doc type: :component
  attr :id, :string, doc: "The unique identifier for the clipboard component element."

  attr :class, :any,
    default: nil,
    doc: "CSS classes to apply to the clipboard component container."

  attr :text, :string,
    default: nil,
    doc:
      "The text to copy to the clipboard. If not provided, it will look for the text content or target selector."

  attr :target_selector, :string,
    default: nil,
    doc: "The CSS selector for the target element to copy from, if no text is provided."

  attr :timeout, :integer,
    default: 2000,
    doc:
      "The timeout duration (in milliseconds) before the clipboard operation is considered failed."

  attr :success_class, :string,
    default: "clipboard-success",
    doc: "CSS class applied to the component when the clipboard copy is successful."

  attr :error_class, :string,
    default: "clipboard-error",
    doc: "CSS class applied to the component when the clipboard copy fails."

  attr :copy_success_text, :string,
    doc: "The success message to display after a successful copy operation."

  attr :copy_error_text, :string,
    doc: "The error message to display after a failed copy operation."

  attr :copy_button_label, :string,
    default: nil,
    doc: "Label for the button used to trigger the copy operation."

  attr :text_description, :string,
    default: nil,
    doc:
      "Optional description text for screen readers, providing more context about the clipboard functionality."

  attr :status_class, :string,
    default: "block mt-2",
    doc: "CSS class for styling the status message shown after a copy operation."

  attr :content_class, :string,
    default: "block mb-2",
    doc: "CSS class for styling the content shown in the clipboard container."

  attr :trigger_class, :string,
    default: nil,
    doc: "CSS class for styling the trigger wrapper."

  attr :show_status_text, :boolean,
    default: true,
    doc: "If true, displays the visual clipboard status text (e.g., 'Copied!'). Default: true."

  attr :dynamic_label, :boolean,
    default: false,
    doc:
      "If true, replaces text inside `.clipboard-label` on copy success/failure. Default: false."

  slot :content, doc: "Slot for custom content to display inside the clipboard container."

  slot :trigger,
    required: true,
    doc:
      "The slot for the button or trigger element that initiates the copy operation. This is a required slot."

  slot :inner_block,
    doc:
      "Slot for additional content or inner components that should be rendered inside the clipboard container."

  attr :rest, :global,
    doc:
      "Global attributes can define defaults which are merged with attributes provided by the caller"

  def clipboard(assigns) do
    assigns =
      assigns
      |> assign_new(:id, fn -> "clipboard-#{random_id()}" end)
      |> assign_new(:copy_success_text, fn -> gettext("Copied!") end)
      |> assign_new(:copy_error_text, fn -> gettext("Copy failed") end)
      |> assign_new(:copy_button_label, fn -> gettext("Copy to clipboard") end)
      |> then(fn new_assigns ->
        new_assigns
        |> assign(:status_id, "#{new_assigns.id}-status")
        |> assign(:content_id, "#{new_assigns.id}-content")
      end)

    ~H"""
    <span
      id={@id}
      class={["clipboard-container", @class]}
      phx-hook="Clipboard"
      phx-track-static
      phx-update="ignore"
      data-timeout={@timeout}
      data-success-class={@success_class}
      data-error-class={@error_class}
      data-clipboard-text={@text}
      data-target-selector={@target_selector}
      data-copy-success-text={@copy_success_text}
      data-copy-error-text={@copy_error_text}
      data-dynamic-label={to_string(@dynamic_label)}
      aria-describedby={@text_description && "#{@id}-description"}
    >
      <span :if={@text_description} id={"#{@id}-description"} class="sr-only">
        {@text_description}
      </span>

      <span
        :if={@text == nil && @target_selector == nil && Enum.count(@content) > 0}
        id={@content_id}
        class={["clipboard-content", @content_class]}
      >
        {render_slot(@content)}
      </span>

      <span
        class={["clipboard-trigger cursor-pointer", @trigger_class]}
        role="button"
        tabindex="0"
        aria-describedby={@status_id}
        aria-pressed="false"
      >
        {render_slot(@trigger)}
      </span>

      <span
        :if={@show_status_text}
        id={@status_id}
        class={["clipboard-status", @status_class]}
        aria-live="polite"
        aria-hidden="true"
        aria-atomic="true"
      ></span>

      {render_slot(@inner_block)}
    </span>
    """
  end
end
