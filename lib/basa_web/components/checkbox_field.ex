defmodule BasaWeb.Components.CheckboxField do
  use Phoenix.Component
  alias Phoenix.HTML.Form
  alias Phoenix.LiveView.Utils
  import BasaWeb.Components.Icon, only: [icon: 1]

  @doc type: :component
  attr :id, :any,
    default: nil,
    doc: "A unique identifier is used to manage state and interaction"

  attr :class, :any, default: nil, doc: "Custom CSS class for additional styling"
  attr :color, :string, default: "primary", doc: "Determines color theme"
  attr :border, :string, default: "extra_small", doc: "Determines border style"
  attr :rounded, :string, default: "small", doc: "Determines the border radius"
  attr :space, :string, default: "medium", doc: "Space between items"
  attr :label_class, :string, default: "block", doc: "Custom CSS class for the label styling"
  attr :wrapper_class, :string, default: nil, doc: "Custom CSS class for the wrapper"
  attr :checkbox_class, :string, default: nil, doc: "Custom CSS class for the wrapper"

  attr :size, :string,
    default: "extra_large",
    doc:
      "Determines the overall size of the elements, including padding, font size, and other items"

  attr :ring, :boolean,
    default: true,
    doc:
      "Determines a ring border on focused input, utilities for creating outline rings with box-shadows."

  attr :reverse, :boolean, default: false, doc: "Switches the order of the element and label"
  attr :checked, :boolean, default: false, doc: "Specifies if the element is checked by default"
  attr :error_icon, :string, default: nil, doc: "Icon to be displayed alongside error messages"
  attr :label, :string, default: nil, doc: "Specifies text for the label"
  attr :multiple, :boolean, default: false, doc: "the multiple flag for select inputs"
  attr :errors, :list, default: [], doc: "List of error messages to be displayed"
  attr :name, :any, default: nil, doc: "Name of input"
  attr :value, :any, default: nil, doc: "Value of input"

  attr :field, Phoenix.HTML.FormField, doc: "a form field struct retrieved from the form"

  attr :rest, :global,
    include: ~w(autocomplete disabled form checked readonly required title autofocus),
    doc:
      "Global attributes can define defaults which are merged with attributes provided by the caller"

  @spec checkbox_field(map()) :: Phoenix.LiveView.Rendered.t()
  def checkbox_field(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    new_id = assigns.id || field.id
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []

    assigns
    |> assign(field: nil)
    |> assign(id: if(assigns.multiple, do: new_id <> "_#{Utils.random_id()}", else: new_id))
    |> assign(:errors, Enum.map(errors, &translate_error(&1)))
    |> assign(
      :name,
      assigns.name || if(assigns.multiple, do: field.name <> "[]", else: field.name)
    )
    |> assign(:value, assigns.value || field.value)
    |> assign_new(:checked, fn ->
      Form.normalize_value("checkbox", assigns[:value])
    end)
    |> checkbox_field()
  end

  def checkbox_field(assigns) do
    ~H"""
    <div class={[
      color_class(@color),
      rounded_size(@rounded),
      border_class(@border),
      size_class(@size),
      space_class(@space),
      @ring && "[&_.checkbox-field-wrapper:focus-within_input]:ring-1",
      @reverse && "[&_.checkbox-field-wrapper]:flex-row-reverse",
      @class
    ]}>
      <.label class={["checkbox-field-wrapper flex items-center w-fit", @wrapper_class]} for={@id}>
        <%= if @value in ["true", "false"] do %>
          <input type="hidden" name={@name} value="false" disabled={@rest[:disabled]} />
        <% else %>
          <input type="hidden" name={@name} value="" disabled={@rest[:disabled]} />
        <% end %>

        <input
          type="checkbox"
          name={@name}
          value={@value}
          id={@id}
          checked={@checked}
          class={["bg-white dark:bg-base-bg-dark checkbox-input", @checkbox_class]}
          {@rest}
        />
        <span :if={@label} class={@label_class}>{@label}</span>
      </.label>

      <.error :for={msg <- @errors} icon={@error_icon}>{msg}</.error>
    </div>
    """
  end

  @doc type: :component
  attr :id, :any,
    default: nil,
    doc: "A unique identifier is used to manage state and interaction"

  attr :class, :any, default: nil, doc: "Custom CSS class for additional styling"
  attr :color, :string, default: "primary", doc: "Determines color theme"
  attr :border, :string, default: "extra_small", doc: "Determines border style"
  attr :rounded, :string, default: "small", doc: "Determines the border radius"
  attr :space, :string, default: "medium", doc: "Space between items"
  attr :label_class, :string, default: "block", doc: "Custom CSS class for the label styling"
  attr :wrapper_class, :string, default: nil, doc: "Custom CSS class for the wrapper"
  attr :checkbox_class, :string, default: nil, doc: "Custom CSS class for the wrapper"
  attr :checkbox_wrapper_class, :string, default: nil, doc: "Custom CSS class for the wrapper"

  attr :variation, :string,
    default: "vertical",
    doc: "Defines the layout orientation of the component"

  attr :size, :string,
    default: "extra_large",
    doc:
      "Determines the overall size of the elements, including padding, font size, and other items"

  attr :ring, :boolean,
    default: true,
    doc:
      "Determines a ring border on focused input, utilities for creating outline rings with box-shadows."

  attr :reverse, :boolean, default: false, doc: "Switches the order of the element and label"
  attr :error_icon, :string, default: nil, doc: "Icon to be displayed alongside error messages"
  attr :errors, :list, default: [], doc: "List of error messages to be displayed"
  attr :name, :any, default: nil, doc: "Name of input"
  attr :value, :any, default: nil, doc: "Value of input"

  attr :rest, :global,
    include: ~w(autocomplete disabled form indeterminate readonly required title autofocus),
    doc:
      "Global attributes can define defaults which are merged with attributes provided by the caller"

  slot :checkbox, required: true do
    attr :value, :string, required: true
    attr :checked, :boolean, required: false
    attr :space, :string, required: false, doc: "Space between items"
  end

  attr :field, Phoenix.HTML.FormField, doc: "a form field struct retrieved from the form"
  slot :inner_block

  @spec group_checkbox(map()) :: Phoenix.LiveView.Rendered.t()
  def group_checkbox(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []

    assigns
    |> assign(field: nil)
    |> assign(id: assigns.id || field.id)
    |> assign(:errors, Enum.map(errors, &translate_error(&1)))
    |> assign(:name, assigns.name || field.name <> "[]")
    |> assign(:value, assigns.value || field.value)
    |> assign(:multiple, true)
    |> group_checkbox()
  end

  def group_checkbox(assigns) do
    ~H"""
    <div class={[
      @variation == "horizontal" && display_class("flex flex-wrap items-center", @class),
      @variation == "vertical" && display_class("flex flex-col", @class),
      variation_gap(@space),
      @class
    ]}>
      {render_slot(@inner_block)}
      <input type="hidden" name={@name} value="" disabled={@rest[:disabled]} />
      <div
        :for={{checkbox, index} <- Enum.with_index(@checkbox, 1)}
        class={[
          color_class(@color),
          rounded_size(@rounded),
          border_class(@border),
          size_class(@size),
          space_class(checkbox[:space] || "small"),
          @ring && "[&_.checkbox-field-wrapper:focus-within_input]:ring-1",
          @reverse && "[&_.checkbox-field-wrapper]:flex-row-reverse",
          @wrapper_class
        ]}
      >
        <.label
          class={["checkbox-field-wrapper flex items-center w-fit", @checkbox_wrapper_class]}
          for={"#{@id}-#{index}"}
        >
          <input
            type="checkbox"
            name={@name}
            id={"#{@id}-#{index}"}
            value={checkbox[:value]}
            checked={checkbox[:checked]}
            class={["bg-white dark:bg-base-bg-dark checkbox-input", @checkbox_class]}
            {@rest}
          />
          <span class={@label_class}>{render_slot(checkbox)}</span>
        </.label>
      </div>
    </div>
    <.error :for={msg <- @errors} icon={@error_icon}>{msg}</.error>
    """
  end

  def checkbox_check(:list, {field, value}, %{params: params, data: data} = _form) do
    if params[Atom.to_string(field)] do
      new_value = if is_atom(value), do: Atom.to_string(value), else: value
      new_value in params[Atom.to_string(field)]
    else
      Map.get(data, field) == value
    end
  end

  def checkbox_check(:boolean, field, %{params: params, data: data} = _form) do
    if params[Atom.to_string(field)] do
      Form.normalize_value("checkbox", params[Atom.to_string(field)])
    else
      Map.get(data, field, false)
    end
  end

  attr :class, :any, default: nil, doc: "Custom CSS class for additional styling"
  attr :for, :string, default: nil, doc: "Specifies the form which is associated with"
  slot :inner_block, required: true, doc: "Inner block that renders HEEx content"

  attr :rest, :global,
    doc:
      "Global attributes can define defaults which are merged with attributes provided by the caller"

  defp label(assigns) do
    ~H"""
    <label for={@for} class={["text-sm font-semibold leading-6", @class]}>
      {render_slot(@inner_block)}
    </label>
    """
  end

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

  defp size_class("extra_small"), do: "[&_.checkbox-field-wrapper_input]:size-2.5"

  defp size_class("small"), do: "[&_.checkbox-field-wrapper_input]:size-3"

  defp size_class("medium"), do: "[&_.checkbox-field-wrapper_input]:size-3.5"

  defp size_class("large"), do: "[&_.checkbox-field-wrapper_input]:size-4"

  defp size_class("extra_large"), do: "[&_.checkbox-field-wrapper_input]:size-5"

  defp size_class(params) when is_binary(params), do: params

  defp rounded_size("extra_small"), do: "[&_.checkbox-field-wrapper_.checkbox-input]:rounded-xs"

  defp rounded_size("small"), do: "[&_.checkbox-field-wrapper_.checkbox-input]:rounded-sm"

  defp rounded_size("medium"), do: "[&_.checkbox-field-wrapper_.checkbox-input]:rounded-md"

  defp rounded_size("large"), do: "[&_.checkbox-field-wrapper_.checkbox-input]:rounded-lg"

  defp rounded_size("extra_large"), do: "[&_.checkbox-field-wrapper_.checkbox-input]:rounded-xl"

  defp rounded_size("full"), do: "[&_.checkbox-field-wrapper_.checkbox-input]:rounded-full"

  defp rounded_size("none"), do: "[&_.checkbox-field-wrapper_.checkbox-input]:rounded-none"

  defp rounded_size(params) when is_binary(params), do: params

  defp border_class("none"), do: "[&_.checkbox-field-wrapper_.checkbox-input]:border-0"
  defp border_class("extra_small"), do: "[&_.checkbox-field-wrapper_.checkbox-input]:border"
  defp border_class("small"), do: "[&_.checkbox-field-wrapper_.checkbox-input]:border-2"
  defp border_class("medium"), do: "[&_.checkbox-field-wrapper_.checkbox-input]:border-[3px]"
  defp border_class("large"), do: "[&_.checkbox-field-wrapper_.checkbox-input]:border-4"
  defp border_class("extra_large"), do: "[&_.checkbox-field-wrapper_.checkbox-input]:border-[5px]"
  defp border_class(params) when is_binary(params), do: params

  defp space_class("none"), do: nil

  defp space_class("extra_small"), do: "[&_.checkbox-field-wrapper]:gap-1"

  defp space_class("small"), do: "[&_.checkbox-field-wrapper]:gap-1.5"

  defp space_class("medium"), do: "[&_.checkbox-field-wrapper]:gap-2"

  defp space_class("large"), do: "[&_.checkbox-field-wrapper]:gap-2.5"

  defp space_class("extra_large"), do: "[&_.checkbox-field-wrapper]:gap-3"

  defp space_class(params) when is_binary(params), do: params

  defp variation_gap("extra_small"), do: "gap-1"

  defp variation_gap("small"), do: "gap-2"

  defp variation_gap("medium"), do: "gap-3"

  defp variation_gap("large"), do: "gap-4"

  defp variation_gap("extra_large"), do: "gap-5"

  defp variation_gap(params) when is_binary(params), do: params

  defp color_class("base") do
    [
      "text-base-text-light dark:text-base-text-dark",
      "[&_.checkbox-field-wrapper_.checkbox-input]:checked:accent-base-form-border-light",
      "dark:[&_.checkbox-field-wrapper_.checkbox-input]:checked:accent-base-form-border-dark",
      "[&_.checkbox-field-wrapper_.checkbox-input]:border-base-form-border-light",
      "dark:[&_.checkbox-field-wrapper_.checkbox-input]:border-base-form-border-dark",
      "[&_.checkbox-field-wrapper:focus-within_.checkbox-input]:ring-base-hover-light dark:[&_.checkbox-field-wrapper:focus-within_.checkbox-input]:ring-base-form-focus-dark"
    ]
  end

  defp color_class("white") do
    [
      "[&_.checkbox-field-wrapper_.checkbox-input]:text-white text-natural-dark",
      "[&_.checkbox-field-wrapper_.checkbox-input]:border-natural-dark",
      "[&_.checkbox-field-wrapper_.checkbox-input]:checked:accent-white",
      "[&_.checkbox-field-wrapper:focus-within_.checkbox-input]:ring-natural-dark"
    ]
  end

  defp color_class("natural") do
    [
      "text-natural-bordered-text-light dark:text-natural-bordered-text-dark",
      "[&_.checkbox-field-wrapper_.checkbox-input]:checked:accent-natural-bordered-text-light",
      "dark:[&_.checkbox-field-wrapper_.checkbox-input]:checked:accent-natural-bordered-text-dark",
      "[&_.checkbox-field-wrapper_.checkbox-input]:border-natural-bordered-text-light",
      "dark:[&_.checkbox-field-wrapper_.checkbox-input]:border-silver-light",
      "[&_.checkbox-field-wrapper:focus-within_.checkbox-input]:ring-natural-light dark:[&_.checkbox-field-wrapper:focus-within_.checkbox-input]:ring-natural-dark"
    ]
  end

  defp color_class("primary") do
    [
      "text-primary-bordered-text-light dark:text-primary-bordered-text-dark",
      "[&_.checkbox-field-wrapper_.checkbox-input]:checked:accent-primary-bordered-text-light",
      "dark:[&_.checkbox-field-wrapper_.checkbox-input]:checked:accent-primary-bordered-text-dark",
      "[&_.checkbox-field-wrapper_.checkbox-input]:border-primary-bordered-text-light",
      "dark:[&_.checkbox-field-wrapper_.checkbox-input]:border-primary-bordered-text-dark",
      "[&_.checkbox-field-wrapper:focus-within_.checkbox-input]:ring-primary-light dark:[&_.checkbox-field-wrapper:focus-within_.checkbox-input]:ring-primary-dark"
    ]
  end

  defp color_class("secondary") do
    [
      "text-secondary-bordered-text-light dark:text-secondary-bordered-text-dark",
      "[&_.checkbox-field-wrapper_.checkbox-input]:checked:accent-secondary-bordered-text-light",
      "dark:[&_.checkbox-field-wrapper_.checkbox-input]:checked:accent-secondary-bordered-text-dark",
      "[&_.checkbox-field-wrapper_.checkbox-input]:border-secondary-bordered-text-light",
      "dark:[&_.checkbox-field-wrapper_.checkbox-input]:border-secondary-bordered-text-dark",
      "[&_.checkbox-field-wrapper:focus-within_.checkbox-input]:ring-secondary-light dark:[&_.checkbox-field-wrapper:focus-within_.checkbox-input]:ring-secondary-dark"
    ]
  end

  defp color_class("success") do
    [
      "text-success-bordered-text-light dark:text-success-bordered-text-dark",
      "[&_.checkbox-field-wrapper_.checkbox-input]:checked:accent-success-bordered-text-light",
      "dark:[&_.checkbox-field-wrapper_.checkbox-input]:checked:accent-success-bordered-text-dark",
      "[&_.checkbox-field-wrapper_.checkbox-input]:border-success-bordered-text-light",
      "dark:[&_.checkbox-field-wrapper_.checkbox-input]:border-success-bordered-text-dark",
      "[&_.checkbox-field-wrapper:focus-within_.checkbox-input]:ring-success-light dark:[&_.checkbox-field-wrapper:focus-within_.checkbox-input]:ring-success-dark"
    ]
  end

  defp color_class("warning") do
    [
      "text-warning-bordered-text-light dark:text-warning-bordered-text-dark",
      "[&_.checkbox-field-wrapper_.checkbox-input]:checked:accent-warning-bordered-text-light",
      "dark:[&_.checkbox-field-wrapper_.checkbox-input]:checked:accent-warning-bordered-text-dark",
      "[&_.checkbox-field-wrapper_.checkbox-input]:border-warning-bordered-text-light",
      "dark:[&_.checkbox-field-wrapper_.checkbox-input]:border-warning-bordered-text-dark",
      "[&_.checkbox-field-wrapper:focus-within_.checkbox-input]:ring-warning-light dark:[&_.checkbox-field-wrapper:focus-within_.checkbox-input]:ring-warning-dark"
    ]
  end

  defp color_class("danger") do
    [
      "text-danger-bordered-text-light dark:text-danger-bordered-text-dark",
      "[&_.checkbox-field-wrapper_.checkbox-input]:checked:accent-danger-bordered-text-light",
      "dark:[&_.checkbox-field-wrapper_.checkbox-input]:checked:accent-danger-bordered-text-dark",
      "[&_.checkbox-field-wrapper_.checkbox-input]:border-danger-bordered-text-light",
      "dark:[&_.checkbox-field-wrapper_.checkbox-input]:border-danger-bordered-text-dark",
      "[&_.checkbox-field-wrapper:focus-within_.checkbox-input]:ring-danger-light dark:[&_.checkbox-field-wrapper:focus-within_.checkbox-input]:ring-danger-dark"
    ]
  end

  defp color_class("info") do
    [
      "text-info-light dark:text-info-hover-dark",
      "[&_.checkbox-field-wrapper_.checkbox-input]:checked:accent-info-light",
      "dark:[&_.checkbox-field-wrapper_.checkbox-input]:checked:accent-info-hover-dark",
      "[&_.checkbox-field-wrapper_.checkbox-input]:border-info-light",
      "dark:[&_.checkbox-field-wrapper_.checkbox-input]:border-info-hover-dark",
      "[&_.checkbox-field-wrapper:focus-within_.checkbox-input]:ring-info-light dark:[&_.checkbox-field-wrapper:focus-within_.checkbox-input]:ring-info-dark"
    ]
  end

  defp color_class("silver") do
    [
      "text-silver-bordered-text-light dark:text-silver-bordered-text-dark",
      "[&_.checkbox-field-wrapper_.checkbox-input]:checked:accent-silver-bordered-text-light",
      "dark:[&_.checkbox-field-wrapper_.checkbox-input]:checked:accent-silver-bordered-text-dark",
      "[&_.checkbox-field-wrapper_.checkbox-input]:border-silver-bordered-text-light",
      "dark:[&_.checkbox-field-wrapper_.checkbox-input]:border-silver-bordered-text-dark",
      "[&_.checkbox-field-wrapper:focus-within_.checkbox-input]:ring-silver-light dark:[&_.checkbox-field-wrapper:focus-within_.checkbox-input]:ring-silver-dark"
    ]
  end

  defp color_class("dark") do
    [
      "[&_.checkbox-field-wrapper_.checkbox-input]:text-default-dark-bg text-default-dark-bg",
      "[&_.checkbox-field-wrapper_.checkbox-input]:checked:accent-default-dark-bg",
      "[&_.checkbox-field-wrapper_.checkbox-input]:border-silver-hover-light",
      "[&_.checkbox-field-wrapper:focus-within_.checkbox-input]:ring-default-dark-bg"
    ]
  end

  defp color_class(params) when is_binary(params), do: params

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
