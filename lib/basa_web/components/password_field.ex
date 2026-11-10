defmodule BasaWeb.Components.PasswordField do
  use Phoenix.Component
  alias Phoenix.LiveView.JS
  import Phoenix.LiveView.Utils, only: [random_id: 0]
  use Gettext, backend: BasaWeb.Gettext
  import BasaWeb.Components.Icon, only: [icon: 1]

  @doc type: :component
  attr :id, :string,
    default: nil,
    doc: "A unique identifier is used to manage state and interaction"

  attr :class, :any, default: nil, doc: "Custom CSS class for additional styling"
  attr :color, :string, default: "natural", doc: "Determines color theme"
  attr :border, :string, default: "extra_small", doc: "Determines border style"
  attr :rounded, :string, default: "small", doc: "Determines the border radius"
  attr :variant, :string, default: "base", doc: "Determines the style"
  attr :description, :string, default: nil, doc: "Determines a short description"
  attr :space, :string, default: "medium", doc: "Space between items"
  attr :placeholder, :string, default: nil, doc: "Specifies text for placeholder"
  attr :description_class, :string, default: "text-[12px]", doc: "Custom classes for description"
  attr :label_class, :string, default: nil, doc: "Custom CSS class for the label styling"
  attr :field_wrapper_class, :string, default: nil, doc: "Custom CSS class field wrapper"
  attr :input_class, :string, default: nil, doc: "Custom CSS class for the input"
  attr :show_pass_class, :string, default: nil, doc: "Custom CSS class for the show password"

  attr :floating_label_class, :string,
    default: nil,
    doc: "Custom CSS class for the floating label"

  attr :description_wrapper_class, :string,
    default: nil,
    doc: "Custom classes for description wrapper"

  attr :size, :string,
    default: "extra_large",
    doc:
      "Determines the overall size of the elements, including padding, font size, and other items"

  attr :show_password, :boolean,
    default: false,
    doc: "Determines whether to show the password toggle button"

  attr :ring, :boolean,
    default: true,
    doc:
      "Determines a ring border on focused input, utilities for creating outline rings with box-shadows."

  attr :floating, :string, default: "none", doc: "none, inner, outer"
  attr :error_icon, :string, default: nil, doc: "Icon to be displayed alongside error messages"
  attr :label, :string, default: nil, doc: "Specifies text for the label"

  slot :start_section, required: false, doc: "Renders heex content in start of an element" do
    attr :class, :any, doc: "Custom CSS class for additional styling"
    attr :icon, :string, doc: "Icon displayed alongside of an item"
  end

  slot :end_section, required: false, doc: "Renders heex content in end of an element" do
    attr :class, :any, doc: "Custom CSS class for additional styling"
    attr :icon, :string, doc: "Icon displayed alongside of an item"
  end

  attr :errors, :list, default: [], doc: "List of error messages to be displayed"
  attr :name, :any, default: nil, doc: "Name of input"
  attr :value, :any, default: nil, doc: "Value of input"

  attr :field, Phoenix.HTML.FormField, doc: "a form field struct retrieved from the form"

  attr :rest, :global,
    include: ~w(autocomplete disabled form maxlength minlength pattern placeholder
        readonly required size spellcheck inputmode title autofocus),
    doc:
      "Global attributes can define defaults which are merged with attributes provided by the caller"

  @spec password_field(map()) :: Phoenix.LiveView.Rendered.t()
  def password_field(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []

    assigns
    |> assign(field: nil, id: assigns.id || field.id || random_id())
    |> assign(:errors, Enum.map(errors, &translate_error(&1)))
    |> assign(:name, assigns.name || field.name)
    |> assign(:value, assigns.value || field.value)
    |> password_field()
  end

  def password_field(%{floating: floating} = assigns) when floating in ["inner", "outer"] do
    assigns = assign(assigns, field: nil, id: assigns.id || random_id() <> "-password-field")

    ~H"""
    <div class={[
      color_variant(@variant, @color, @floating),
      rounded_size(@rounded),
      border_class(@border, @variant),
      size_class(@size),
      space_class(@space),
      @ring && "[&_.password-field-wrapper]:focus-within:ring-[0.03rem] leading-6",
      @class
    ]}>
      <div :if={@description} class={@description_class}>
        {@description}
      </div>
      <div class={[
        "password-field-wrapper transition-all ease-in-out duration-200 w-full flex flex-nowrap",
        @errors != [] && "password-field-error",
        @field_wrapper_class
      ]}>
        <div
          :if={@start_section}
          class={[
            "flex items-center justify-center shrink-0 ps-2",
            @start_section[:class]
          ]}
        >
          {render_slot(@start_section)}
        </div>
        <div class="relative w-full z-[2]">
          <input
            type="password"
            name={@name}
            id={@id}
            value={@value}
            placeholder=" "
            class={[
              "disabled:opacity-80 block w-full z-[2] focus:ring-0 placeholder:text-transparent pb-1 pt-2.5 px-2",
              "text-[16px] sm:text-[length:inherit] appearance-none bg-transparent border-0 focus:outline-hidden peer",
              @input_class
            ]}
            {@rest}
          />

          <label
            :if={@label}
            class={[
              "floating-label px-1 start-1 -z-[1] absolute text-xs duration-300 transform scale-75 origin-[0]",
              variant_label_position(@floating),
              @floating_label_class
            ]}
            for={@id}
          >
            {@label}
          </label>
        </div>

        <div
          :if={@end_section}
          class={["flex items-center justify-center shrink-0 pe-2", @end_section[:class]]}
        >
          {render_slot(@end_section)}
        </div>
        <div
          :if={@show_password}
          class={["flex items-center justify-center shrink-0 pe-2", @show_pass_class]}
        >
          <button
            type="button"
            class="leading-6 cursor-pointer focus:outline-hidden"
            aria-label={gettext("Show password")}
            aria-pressed="false"
            phx-click={
              JS.toggle_class("hero-eye-slash password-field-icon")
              |> JS.toggle_attribute({"type", "password", "text"}, to: "##{@id}")
              |> JS.toggle_attribute({"aria-pressed", "true", "false"})
            }
          >
            <.icon name="hero-eye" class="password-field-icon" />
          </button>
        </div>
      </div>

      <.error :for={msg <- @errors} icon={@error_icon}>{msg}</.error>
    </div>
    """
  end

  def password_field(assigns) do
    assigns = assign(assigns, field: nil, id: assigns.id || random_id() <> "-password-field")

    ~H"""
    <div class={[
      color_variant(@variant, @color, @floating),
      rounded_size(@rounded),
      border_class(@border, @variant),
      size_class(@size),
      space_class(@space),
      @ring && "[&_.password-field-wrapper]:focus-within:ring-[0.03rem] leading-6",
      @class
    ]}>
      <div :if={@label || @description} class={["password-label-wrapper", @description_wrapper_class]}>
        <.label :if={@label} for={@id} class={@label_class}>{@label}</.label>
        <div :if={@description} class={@description_class}>
          {@description}
        </div>
      </div>

      <div class={[
        "password-field-wrapper overflow-hidden transition-all ease-in-out duration-200 flex items-center flex-nowrap",
        @errors != [] && "password-field-error",
        @field_wrapper_class
      ]}>
        <div
          :if={@start_section}
          class={[
            "flex items-center justify-center shrink-0 ps-2",
            @start_section[:class]
          ]}
        >
          {render_slot(@start_section)}
        </div>

        <input
          type="password"
          name={@name}
          id={@id}
          value={@value}
          placeholder={@placeholder}
          class={[
            "flex-1 py-1 px-2 text-sm disabled:opacity-80 block w-full appearance-none",
            "bg-transparent border-0 focus:outline-hidden focus:ring-0",
            @input_class
          ]}
          {@rest}
        />

        <div
          :if={@end_section}
          class={["flex items-center justify-center shrink-0 pe-2", @end_section[:class]]}
        >
          {render_slot(@end_section)}
        </div>
        <div
          :if={@show_password}
          class={["flex items-center justify-center shrink-0 pe-2", @show_pass_class]}
        >
          <button
            type="button"
            class="leading-6 cursor-pointer focus:outline-hidden"
            aria-label={gettext("Show password")}
            aria-pressed="false"
            phx-click={
              JS.toggle_class("hero-eye-slash password-field-icon")
              |> JS.toggle_attribute({"type", "password", "text"}, to: "##{@id}")
              |> JS.toggle_attribute({"aria-pressed", "true", "false"})
            }
          >
            <.icon name="hero-eye" class="password-field-icon" />
          </button>
        </div>
      </div>

      <.error :for={msg <- @errors} icon={@error_icon}>{msg}</.error>
    </div>
    """
  end

  attr :for, :string, default: nil, doc: "Specifies the form which is associated with"
  attr :class, :any, default: nil, doc: "Custom CSS class for additional styling"
  slot :inner_block, required: true, doc: "Inner block that renders HEEx content"

  defp label(assigns) do
    ~H"""
    <label for={@for} class={["font-semibold", @class]}>
      {render_slot(@inner_block)}
    </label>
    """
  end

  attr :icon, :string, default: nil, doc: "Icon displayed alongside of an item"
  slot :inner_block, required: true, doc: "Inner block that renders HEEx content"

  defp error(assigns) do
    ~H"""
    <p class="mt-3 flex items-center gap-3 text-sm text-rose-700">
      <.icon :if={!is_nil(@icon)} name={@icon} class="shrink-0" />
      {render_slot(@inner_block)}
    </p>
    """
  end

  defp variant_label_position("outer") do
    [
      "-translate-y-4 top-2 origin-[0] peer-focus:px-1 peer-placeholder-shown:scale-100",
      "peer-placeholder-shown:-translate-y-1/2 peer-placeholder-shown:top-1/2 peer-focus:top-2 peer-focus:scale-75 peer-focus:-translate-y-4",
      "rtl:peer-focus:translate-x-1/4 rtl:peer-focus:left-auto"
    ]
  end

  defp variant_label_position("inner") do
    [
      "-translate-y-4 scale-75 top-4 origin-[0] peer-placeholder-shown:scale-100 peer-placeholder-shown:translate-y-0",
      "peer-focus:scale-75 peer-focus:-translate-y-4 rtl:peer-focus:translate-x-1/4 rtl:peer-focus:left-auto"
    ]
  end

  defp size_class("extra_small") do
    "[&_.password-field-wrapper_input]:h-8 [&_.password-field-wrapper_.password-field-icon]:size-3"
  end

  defp size_class("small") do
    "[&_.password-field-wrapper_input]:h-9 [&_.password-field-wrapper_.password-field-icon]:size-3.5"
  end

  defp size_class("medium") do
    "[&_.password-field-wrapper_input]:h-10 [&_.password-field-wrapper_.password-field-icon]:size-4"
  end

  defp size_class("large") do
    "[&_.password-field-wrapper_input]:h-11 [&_.password-field-wrapper_.password-field-icon]:size-5"
  end

  defp size_class("extra_large") do
    "[&_.password-field-wrapper_input]:h-12 [&_.password-field-wrapper_.password-field-icon]:size-6"
  end

  defp size_class(params) when is_binary(params), do: params

  defp rounded_size("extra_small"), do: "[&_.password-field-wrapper]:rounded-xs"

  defp rounded_size("small"), do: "[&_.password-field-wrapper]:rounded-sm"

  defp rounded_size("medium"), do: "[&_.password-field-wrapper]:rounded-md"

  defp rounded_size("large"), do: "[&_.password-field-wrapper]:rounded-lg"

  defp rounded_size("extra_large"), do: "[&_.password-field-wrapper]:rounded-xl"

  defp rounded_size("full"), do: "[&_.password-field-wrapper]:rounded-full"

  defp rounded_size("none"), do: nil

  defp rounded_size(params) when is_binary(params), do: params

  defp border_class(_, variant) when variant in ["default", "shadow", "transparent"],
    do: nil

  defp border_class("none", _), do: "[&_.password-field-wrapper]:border-0"
  defp border_class("extra_small", _), do: "[&_.password-field-wrapper]:border"
  defp border_class("small", _), do: "[&_.password-field-wrapper]:border-2"
  defp border_class("medium", _), do: "[&_.password-field-wrapper]:border-[3px]"
  defp border_class("large", _), do: "[&_.password-field-wrapper]:border-4"
  defp border_class("extra_large", _), do: "[&_.password-field-wrapper]:border-[5px]"
  defp border_class(params, _) when is_binary(params), do: params

  defp space_class("none"), do: nil

  defp space_class("extra_small"), do: "space-y-1"

  defp space_class("small"), do: "space-y-1.5"

  defp space_class("medium"), do: "space-y-2"

  defp space_class("large"), do: "space-y-2.5"

  defp space_class("extra_large"), do: "space-y-3"

  defp space_class(params) when is_binary(params), do: params

  defp color_variant("base", _, floating) do
    [
      "[&_.password-field-wrapper:not(:has(.password-field-error))]:bg-white",
      "dark:[&_.password-field-wrapper:not(:has(.password-field-error))]:bg-base-bg-dark",
      "text-base-text-light dark:text-base-text-dark [&_.password-field-wrapper:not(:has(.password-field-error))]:border-base-border-light",
      "dark:[&_.password-field-wrapper:not(:has(.password-field-error))]:border-base-border-dark",
      "[&_.password-field-wrapper.password-field-error]:border-rose-700",
      "[&_.password-field-wrapper>input]:placeholder:text-base-text-light dark:[&_.password-field-wrapper>input]:placeholder:text-base-text-dark",
      "focus-within:[&_.password-field-wrapper]:ring-base-border-light dark:focus-within:[&_.password-field-wrapper]:ring-base-border-light",
      "[&_.password-field-wrapper]:shadow-xs",
      floating == "outer" &&
        "[&_.password-field-wrapper_.floating-label]:bg-white dark:[&_.password-field-wrapper_.floating-label]:bg-base-bg-dark"
    ]
  end

  defp color_variant("outline", "natural", floating) do
    [
      "text-natural-light dark:text-natural-dark [&_.password-field-wrapper:not(:has(.password-field-error))]:border-natural-light",
      "dark:[&_.password-field-wrapper:not(:has(.password-field-error))]:border-natural-dark",
      "[&_.password-field-wrapper.password-field-error]:border-rose-700",
      "[&_.password-field-wrapper>input]:placeholder:text-natural-light dark:[&_.password-field-wrapper>input]:placeholder:text-natural-dark",
      "focus-within:[&_.password-field-wrapper]:ring-natural-light dark:focus-within:[&_.password-field-wrapper]:ring-natural-dark",
      floating == "outer" &&
        "[&_.password-field-wrapper_.floating-label]:bg-white dark:[&_.password-field-wrapper_.floating-label]:bg-default-dark-bg"
    ]
  end

  defp color_variant("outline", "primary", floating) do
    [
      "text-primary-light dark:text-primary-dark [&_.password-field-wrapper:not(:has(.password-field-error))]:border-primary-light",
      "dark:[&_.password-field-wrapper:not(:has(.password-field-error))]:border-primary-dark",
      "[&_.password-field-wrapper.password-field-error]:border-rose-700",
      "[&_.password-field-wrapper>input]:placeholder:text-primary-light dark:[&_.password-field-wrapper>input]:placeholder:text-primary-dark",
      "focus-within:[&_.password-field-wrapper]:ring-primary-light dark:focus-within:[&_.password-field-wrapper]:ring-primary-dark",
      floating == "outer" &&
        "[&_.password-field-wrapper_.floating-label]:bg-white dark:[&_.password-field-wrapper_.floating-label]:bg-default-dark-bg"
    ]
  end

  defp color_variant("outline", "secondary", floating) do
    [
      "text-secondary-light dark:text-secondary-dark [&_.password-field-wrapper:not(:has(.password-field-error))]:border-secondary-light",
      "dark:[&_.password-field-wrapper:not(:has(.password-field-error))]:border-secondary-dark",
      "[&_.password-field-wrapper.password-field-error]:border-rose-700",
      "[&_.password-field-wrapper>input]:placeholder:text-secondary-light dark:[&_.password-field-wrapper>input]:placeholder:text-secondary-dark",
      "focus-within:[&_.password-field-wrapper]:ring-secondary-light dark:focus-within:[&_.password-field-wrapper]:ring-secondary-dark",
      floating == "outer" &&
        "[&_.password-field-wrapper_.floating-label]:bg-white dark:[&_.password-field-wrapper_.floating-label]:bg-default-dark-bg"
    ]
  end

  defp color_variant("outline", "success", floating) do
    [
      "text-success-light dark:text-success-dark [&_.password-field-wrapper:not(:has(.password-field-error))]:border-success-light",
      "dark:[&_.password-field-wrapper:not(:has(.password-field-error))]:border-success-dark",
      "[&_.password-field-wrapper.password-field-error]:border-rose-700",
      "[&_.password-field-wrapper>input]:placeholder:text-success-light dark:[&_.password-field-wrapper>input]:placeholder:text-success-dark",
      "focus-within:[&_.password-field-wrapper]:ring-success-light dark:focus-within:[&_.password-field-wrapper]:ring-success-dark",
      floating == "outer" &&
        "[&_.password-field-wrapper_.floating-label]:bg-white dark:[&_.password-field-wrapper_.floating-label]:bg-default-dark-bg"
    ]
  end

  defp color_variant("outline", "warning", floating) do
    [
      "text-warning-light dark:text-warning-dark [&_.password-field-wrapper:not(:has(.password-field-error))]:border-warning-light",
      "dark:[&_.password-field-wrapper:not(:has(.password-field-error))]:border-warning-dark",
      "[&_.password-field-wrapper.password-field-error]:border-rose-700",
      "[&_.password-field-wrapper>input]:placeholder:text-warning-light dark:[&_.password-field-wrapper>input]:placeholder:text-warning-dark",
      "focus-within:[&_.password-field-wrapper]:ring-warning-light dark:focus-within:[&_.password-field-wrapper]:ring-warning-dark",
      floating == "outer" &&
        "[&_.password-field-wrapper_.floating-label]:bg-white dark:[&_.password-field-wrapper_.floating-label]:bg-default-dark-bg"
    ]
  end

  defp color_variant("outline", "danger", floating) do
    [
      "text-danger-light dark:text-danger-dark [&_.password-field-wrapper:not(:has(.password-field-error))]:border-danger-light",
      "dark:[&_.password-field-wrapper:not(:has(.password-field-error))]:border-danger-dark",
      "[&_.password-field-wrapper.password-field-error]:border-rose-700",
      "[&_.password-field-wrapper>input]:placeholder:text-danger-light dark:[&_.password-field-wrapper>input]:placeholder:text-danger-dark",
      "focus-within:[&_.password-field-wrapper]:ring-danger-light dark:focus-within:[&_.password-field-wrapper]:ring-danger-dark",
      floating == "outer" &&
        "[&_.password-field-wrapper_.floating-label]:bg-white dark:[&_.password-field-wrapper_.floating-label]:bg-default-dark-bg"
    ]
  end

  defp color_variant("outline", "info", floating) do
    [
      "text-info-light dark:text-info-dark [&_.password-field-wrapper:not(:has(.password-field-error))]:border-info-light",
      "dark:[&_.password-field-wrapper:not(:has(.password-field-error))]:border-info-dark",
      "[&_.password-field-wrapper.password-field-error]:border-rose-700",
      "[&_.password-field-wrapper>input]:placeholder:text-info-light dark:[&_.password-field-wrapper>input]:placeholder:text-info-dark",
      "focus-within:[&_.password-field-wrapper]:ring-info-light dark:focus-within:[&_.password-field-wrapper]:ring-info-dark",
      floating == "outer" &&
        "[&_.password-field-wrapper_.floating-label]:bg-white dark:[&_.password-field-wrapper_.floating-label]:bg-default-dark-bg"
    ]
  end

  defp color_variant("outline", "silver", floating) do
    [
      "text-silver-light dark:text-silver-dark [&_.password-field-wrapper:not(:has(.password-field-error))]:border-silver-light",
      "dark:[&_.password-field-wrapper:not(:has(.password-field-error))]:border-silver-dark",
      "[&_.password-field-wrapper.password-field-error]:border-rose-700",
      "[&_.password-field-wrapper>input]:placeholder:text-silver-light dark:[&_.password-field-wrapper>input]:placeholder:text-silver-dark",
      "focus-within:[&_.password-field-wrapper]:ring-silver-light dark:focus-within:[&_.password-field-wrapper]:ring-silver-dark",
      floating == "outer" &&
        "[&_.password-field-wrapper_.floating-label]:bg-white dark:[&_.password-field-wrapper_.floating-label]:bg-default-dark-bg"
    ]
  end

  defp color_variant("default", "white", floating) do
    [
      "[&_.password-field-wrapper]:bg-white text-form-white-text",
      "[&_.password-field-wrapper.password-field-error]:border-rose-700",
      "[&_.password-field-wrapper>input]:placeholder:text-form-white-text focus-within:[&_.password-field-wrapper]:ring-form-white-focus",
      floating == "outer" && "[&_.password-field-wrapper_.floating-label]:bg-white"
    ]
  end

  defp color_variant("default", "natural", floating) do
    [
      "text-black dark:text-white [&_.password-field-wrapper:not(:has(.password-field-error))]:bg-natural-light",
      "dark:[&_.password-field-wrapper:not(:has(.password-field-error))]:bg-natural-dark",
      "[&_.password-field-wrapper.password-field-error]:bg-rose-700",
      "[&_.password-field-wrapper>input]:placeholder:text-white dark:[&_.password-field-wrapper>input]:placeholder:text-black",
      "[&_.password-field-wrapper>input]:text-white dark:[&_.password-field-wrapper>input]:text-black",
      "focus-within:[&_.password-field-wrapper]:ring-natural-light dark:focus-within:[&_.password-field-wrapper]:ring-natural-dark",
      floating == "outer" &&
        "[&_.password-field-wrapper_.floating-label]:bg-natural-light dark:[&_.password-field-wrapper_.floating-label]:bg-natural-dark"
    ]
  end

  defp color_variant("default", "primary", floating) do
    [
      "text-black dark:text-white [&_.password-field-wrapper:not(:has(.password-field-error))]:bg-primary-light",
      "dark:[&_.password-field-wrapper:not(:has(.password-field-error))]:bg-primary-dark",
      "[&_.password-field-wrapper.password-field-error]:bg-rose-700",
      "[&_.password-field-wrapper>input]:placeholder:text-white dark:[&_.password-field-wrapper>input]:placeholder:text-black",
      "[&_.password-field-wrapper>input]:text-white dark:[&_.password-field-wrapper>input]:text-black",
      "focus-within:[&_.password-field-wrapper]:ring-primary-light dark:focus-within:[&_.password-field-wrapper]:ring-primary-dark",
      floating == "outer" &&
        "[&_.password-field-wrapper_.floating-label]:bg-primary-light dark:[&_.password-field-wrapper_.floating-label]:bg-primary-dark"
    ]
  end

  defp color_variant("default", "secondary", floating) do
    [
      "text-black dark:text-white [&_.password-field-wrapper:not(:has(.password-field-error))]:bg-secondary-light",
      "dark:[&_.password-field-wrapper:not(:has(.password-field-error))]:bg-secondary-dark",
      "[&_.password-field-wrapper.password-field-error]:bg-rose-700",
      "[&_.password-field-wrapper>input]:placeholder:text-white dark:[&_.password-field-wrapper>input]:placeholder:text-black",
      "[&_.password-field-wrapper>input]:text-white dark:[&_.password-field-wrapper>input]:text-black",
      "focus-within:[&_.password-field-wrapper]:ring-secondary-light dark:focus-within:[&_.password-field-wrapper]:ring-secondary-dark",
      floating == "outer" &&
        "[&_.password-field-wrapper_.floating-label]:bg-secondary-light dark:[&_.password-field-wrapper_.floating-label]:bg-secondary-dark"
    ]
  end

  defp color_variant("default", "success", floating) do
    [
      "text-black dark:text-white [&_.password-field-wrapper:not(:has(.password-field-error))]:bg-success-light",
      "dark:[&_.password-field-wrapper:not(:has(.password-field-error))]:bg-success-dark",
      "[&_.password-field-wrapper.password-field-error]:bg-rose-700",
      "[&_.password-field-wrapper>input]:placeholder:text-white dark:[&_.password-field-wrapper>input]:placeholder:text-black",
      "[&_.password-field-wrapper>input]:text-white dark:[&_.password-field-wrapper>input]:text-black",
      "focus-within:[&_.password-field-wrapper]:ring-success-light dark:focus-within:[&_.password-field-wrapper]:ring-success-dark",
      floating == "outer" &&
        "[&_.password-field-wrapper_.floating-label]:bg-success-light dark:[&_.password-field-wrapper_.floating-label]:bg-success-dark"
    ]
  end

  defp color_variant("default", "warning", floating) do
    [
      "text-black dark:text-white [&_.password-field-wrapper:not(:has(.password-field-error))]:bg-warning-light",
      "dark:[&_.password-field-wrapper:not(:has(.password-field-error))]:bg-warning-dark",
      "[&_.password-field-wrapper.password-field-error]:bg-rose-700",
      "[&_.password-field-wrapper>input]:placeholder:text-white dark:[&_.password-field-wrapper>input]:placeholder:text-black",
      "[&_.password-field-wrapper>input]:text-white dark:[&_.password-field-wrapper>input]:text-black",
      "focus-within:[&_.password-field-wrapper]:ring-warning-light dark:focus-within:[&_.password-field-wrapper]:ring-warning-dark",
      floating == "outer" &&
        "[&_.password-field-wrapper_.floating-label]:bg-warning-light dark:[&_.password-field-wrapper_.floating-label]:bg-warning-dark"
    ]
  end

  defp color_variant("default", "danger", floating) do
    [
      "text-black dark:text-white [&_.password-field-wrapper:not(:has(.password-field-error))]:bg-danger-light",
      "dark:[&_.password-field-wrapper:not(:has(.password-field-error))]:bg-danger-dark",
      "[&_.password-field-wrapper.password-field-error]:bg-rose-700",
      "[&_.password-field-wrapper>input]:placeholder:text-white dark:[&_.password-field-wrapper>input]:placeholder:text-black",
      "[&_.password-field-wrapper>input]:text-white dark:[&_.password-field-wrapper>input]:text-black",
      "focus-within:[&_.password-field-wrapper]:ring-danger-light dark:focus-within:[&_.password-field-wrapper]:ring-danger-dark",
      floating == "outer" &&
        "[&_.password-field-wrapper_.floating-label]:bg-danger-light dark:[&_.password-field-wrapper_.floating-label]:bg-danger-dark"
    ]
  end

  defp color_variant("default", "info", floating) do
    [
      "text-black dark:text-white [&_.password-field-wrapper:not(:has(.password-field-error))]:bg-info-light",
      "dark:[&_.password-field-wrapper:not(:has(.password-field-error))]:bg-info-dark",
      "[&_.password-field-wrapper.password-field-error]:bg-rose-700",
      "[&_.password-field-wrapper>input]:placeholder:text-white dark:[&_.password-field-wrapper>input]:placeholder:text-black",
      "[&_.password-field-wrapper>input]:text-white dark:[&_.password-field-wrapper>input]:text-black",
      "focus-within:[&_.password-field-wrapper]:ring-info-light dark:focus-within:[&_.password-field-wrapper]:ring-info-dark",
      floating == "outer" &&
        "[&_.password-field-wrapper_.floating-label]:bg-info-light dark:[&_.password-field-wrapper_.floating-label]:bg-info-dark"
    ]
  end

  defp color_variant("default", "silver", floating) do
    [
      "text-black dark:text-white [&_.password-field-wrapper:not(:has(.password-field-error))]:bg-silver-light",
      "dark:[&_.password-field-wrapper:not(:has(.password-field-error))]:bg-silver-dark",
      "[&_.password-field-wrapper.password-field-error]:bg-rose-700",
      "[&_.password-field-wrapper>input]:placeholder:text-white dark:[&_.password-field-wrapper>input]:placeholder:text-black",
      "[&_.password-field-wrapper>input]:text-white dark:[&_.password-field-wrapper>input]:text-black",
      "focus-within:[&_.password-field-wrapper]:ring-silver-light dark:focus-within:[&_.password-field-wrapper]:ring-silver-dark",
      floating == "outer" &&
        "[&_.password-field-wrapper_.floating-label]:bg-silver-light dark:[&_.password-field-wrapper_.floating-label]:bg-silver-dark"
    ]
  end

  defp color_variant("default", "dark", floating) do
    [
      "[&_.password-field-wrapper]:bg-default-dark-bg text-default-dark-bg [&_.password-field-wrapper]:text-base-text-dark",
      "[&_.password-field-wrapper.password-field-error]:border-rose-700",
      "[&_.password-field-wrapper>input]:placeholder:text-base-text-dark focus-within:[&_.password-field-wrapper]:ring-bordered-dark-border",
      floating == "outer" && "[&_.password-field-wrapper_.floating-label]:bg-default-dark-bg"
    ]
  end

  defp color_variant("bordered", "white", floating) do
    [
      "[&_.password-field-wrapper]:bg-white [&_.password-field-wrapper]:border-transparent text-form-white-text",
      "[&_.password-field-wrapper>input]:placeholder:text-form-white-text",
      floating == "outer" && "[&_.password-field-wrapper_.floating-label]:bg-white"
    ]
  end

  defp color_variant("bordered", "natural", floating) do
    [
      "text-natural-bordered-text-light dark:text-natural-bordered-text-dark [&_.password-field-wrapper:not(:has(.password-field-error))]:border-natural-bordered-text-light",
      "[&_.password-field-wrapper:not(:has(.password-field-error))]:bg-natural-bordered-bg-light",
      "dark:[&_.password-field-wrapper:not(:has(.password-field-error))]:bg-natural-bordered-bg-dark",
      "dark:[&_.password-field-wrapper:not(:has(.password-field-error))]:border-silver-light",
      "[&_.password-field-wrapper.password-field-error]:bg-rose-700",
      "[&_.password-field-wrapper>input]:placeholder:text-natural-bordered-text-light dark:[&_.password-field-wrapper>input]:placeholder:text-natural-bordered-text-dark",
      "focus-within:[&_.password-field-wrapper]:ring-natural-light dark:focus-within:[&_.password-field-wrapper]:ring-natural-dark",
      floating == "outer" &&
        "[&_.password-field-wrapper_.floating-label]:bg-silver-light dark:[&_.password-field-wrapper_.floating-label]:bg-silver-dark"
    ]
  end

  defp color_variant("bordered", "primary", floating) do
    [
      "text-primary-bordered-text-light dark:text-primary-bordered-text-dark [&_.password-field-wrapper:not(:has(.password-field-error))]:border-primary-bordered-text-light",
      "[&_.password-field-wrapper:not(:has(.password-field-error))]:bg-primary-bordered-bg-light",
      "dark:[&_.password-field-wrapper:not(:has(.password-field-error))]:bg-natural-bordered-bg-dark",
      "dark:[&_.password-field-wrapper:not(:has(.password-field-error))]:border-primary-bordered-text-dark",
      "[&_.password-field-wrapper.password-field-error]:bg-rose-700",
      "[&_.password-field-wrapper>input]:placeholder:text-primary-bordered-text-light dark:[&_.password-field-wrapper>input]:placeholder:text-primary-bordered-text-dark",
      "focus-within:[&_.password-field-wrapper]:ring-primary-light dark:focus-within:[&_.password-field-wrapper]:ring-primary-dark",
      floating == "outer" &&
        "[&_.password-field-wrapper_.floating-label]:bg-silver-light dark:[&_.password-field-wrapper_.floating-label]:bg-silver-dark"
    ]
  end

  defp color_variant("bordered", "secondary", floating) do
    [
      "text-secondary-bordered-text-light dark:text-secondary-bordered-text-dark [&_.password-field-wrapper:not(:has(.password-field-error))]:border-secondary-bordered-text-light",
      "[&_.password-field-wrapper:not(:has(.password-field-error))]:bg-secondary-bordered-bg-light",
      "dark:[&_.password-field-wrapper:not(:has(.password-field-error))]:bg-secondary-bordered-bg-dark",
      "dark:[&_.password-field-wrapper:not(:has(.password-field-error))]:border-secondary-bordered-text-dark",
      "[&_.password-field-wrapper.password-field-error]:bg-rose-700",
      "[&_.password-field-wrapper>input]:placeholder:text-secondary-bordered-text-light dark:[&_.password-field-wrapper>input]:placeholder:text-secondary-bordered-text-dark",
      "focus-within:[&_.password-field-wrapper]:ring-secondary-light dark:focus-within:[&_.password-field-wrapper]:ring-secondary-dark",
      floating == "outer" &&
        "[&_.password-field-wrapper_.floating-label]:bg-silver-light dark:[&_.password-field-wrapper_.floating-label]:bg-silver-dark"
    ]
  end

  defp color_variant("bordered", "success", floating) do
    [
      "text-success-bordered-text-light dark:text-success-bordered-text-dark [&_.password-field-wrapper:not(:has(.password-field-error))]:border-success-bordered-text-light",
      "[&_.password-field-wrapper:not(:has(.password-field-error))]:bg-success-bordered-bg-light",
      "dark:[&_.password-field-wrapper:not(:has(.password-field-error))]:bg-success-bordered-bg-dark",
      "dark:[&_.password-field-wrapper:not(:has(.password-field-error))]:border-success-bordered-text-dark",
      "[&_.password-field-wrapper.password-field-error]:bg-rose-700",
      "[&_.password-field-wrapper>input]:placeholder:text-success-bordered-text-light dark:[&_.password-field-wrapper>input]:placeholder:text-success-bordered-text-dark",
      "focus-within:[&_.password-field-wrapper]:ring-success-light dark:focus-within:[&_.password-field-wrapper]:ring-success-dark",
      floating == "outer" &&
        "[&_.password-field-wrapper_.floating-label]:bg-silver-light dark:[&_.password-field-wrapper_.floating-label]:bg-silver-dark"
    ]
  end

  defp color_variant("bordered", "warning", floating) do
    [
      "text-warning-bordered-text-light dark:text-warning-bordered-text-dark [&_.password-field-wrapper:not(:has(.password-field-error))]:border-warning-bordered-text-light",
      "[&_.password-field-wrapper:not(:has(.password-field-error))]:bg-warning-bordered-bg-light",
      "dark:[&_.password-field-wrapper:not(:has(.password-field-error))]:bg-warning-bordered-bg-dark",
      "dark:[&_.password-field-wrapper:not(:has(.password-field-error))]:border-warning-bordered-text-dark",
      "[&_.password-field-wrapper.password-field-error]:bg-rose-700",
      "[&_.password-field-wrapper>input]:placeholder:text-warning-bordered-text-light dark:[&_.password-field-wrapper>input]:placeholder:text-warning-bordered-text-dark",
      "focus-within:[&_.password-field-wrapper]:ring-warning-light dark:focus-within:[&_.password-field-wrapper]:ring-warning-dark",
      floating == "outer" &&
        "[&_.password-field-wrapper_.floating-label]:bg-silver-light dark:[&_.password-field-wrapper_.floating-label]:bg-silver-dark"
    ]
  end

  defp color_variant("bordered", "danger", floating) do
    [
      "text-danger-bordered-text-light dark:text-danger-bordered-text-dark [&_.password-field-wrapper:not(:has(.password-field-error))]:border-danger-bordered-text-light",
      "[&_.password-field-wrapper:not(:has(.password-field-error))]:bg-danger-bordered-bg-light",
      "dark:[&_.password-field-wrapper:not(:has(.password-field-error))]:bg-danger-bordered-bg-dark",
      "dark:[&_.password-field-wrapper:not(:has(.password-field-error))]:border-danger-bordered-text-dark",
      "[&_.password-field-wrapper.password-field-error]:bg-rose-700",
      "[&_.password-field-wrapper>input]:placeholder:text-danger-bordered-text-light dark:[&_.password-field-wrapper>input]:placeholder:text-danger-bordered-text-dark",
      "focus-within:[&_.password-field-wrapper]:ring-danger-light dark:focus-within:[&_.password-field-wrapper]:ring-danger-dark",
      floating == "outer" &&
        "[&_.password-field-wrapper_.floating-label]:bg-silver-light dark:[&_.password-field-wrapper_.floating-label]:bg-silver-dark"
    ]
  end

  defp color_variant("bordered", "info", floating) do
    [
      "text-info-bordered-text-light dark:text-info-bordered-text-dark [&_.password-field-wrapper:not(:has(.password-field-error))]:border-info-bordered-text-light",
      "[&_.password-field-wrapper:not(:has(.password-field-error))]:bg-info-bordered-bg-light",
      "dark:[&_.password-field-wrapper:not(:has(.password-field-error))]:bg-info-bordered-bg-dark",
      "dark:[&_.password-field-wrapper:not(:has(.password-field-error))]:border-info-hover-dark",
      "[&_.password-field-wrapper.password-field-error]:bg-rose-700",
      "[&_.password-field-wrapper>input]:placeholder:text-info-light dark:[&_.password-field-wrapper>input]:placeholder:text-info-hover-dark",
      "focus-within:[&_.password-field-wrapper]:ring-info-light dark:focus-within:[&_.password-field-wrapper]:ring-info-dark",
      floating == "outer" &&
        "[&_.password-field-wrapper_.floating-label]:bg-silver-light dark:[&_.password-field-wrapper_.floating-label]:bg-silver-dark"
    ]
  end

  defp color_variant("bordered", "silver", floating) do
    [
      "text-silver-bordered-text-light dark:text-silver-bordered-text-dark [&_.password-field-wrapper:not(:has(.password-field-error))]:border-silver-bordered-text-light",
      "[&_.password-field-wrapper:not(:has(.password-field-error))]:bg-silver-bordered-bg-light",
      "dark:[&_.password-field-wrapper:not(:has(.password-field-error))]:bg-silver-bordered-bg-dark",
      "dark:[&_.password-field-wrapper:not(:has(.password-field-error))]:border-silver-bordered-text-dark",
      "[&_.password-field-wrapper.password-field-error]:bg-rose-700",
      "[&_.password-field-wrapper>input]:placeholder:text-silver-bordered-text-light dark:[&_.password-field-wrapper>input]:placeholder:text-silver-bordered-text-dark",
      "focus-within:[&_.password-field-wrapper]:ring-silver-light dark:focus-within:[&_.password-field-wrapper]:ring-silver-dark",
      floating == "outer" &&
        "[&_.password-field-wrapper_.floating-label]:bg-silver-light dark:[&_.password-field-wrapper_.floating-label]:bg-silver-dark"
    ]
  end

  defp color_variant("bordered", "dark", floating) do
    [
      "[&_.password-field-wrapper]:bg-default-dark-bg text-default-dark-bg [&_.password-field-wrapper]:border-bordered-dark-border text-base-text-dark",
      "[&_.password-field-wrapper>input]:placeholder:text-base-text-dark focus-within:[&_.password-field-wrapper]:ring-bordered-dark-border",
      floating == "outer" && "[&_.password-field-wrapper_.floating-label]:bg-default-dark-bg"
    ]
  end

  defp color_variant("shadow", "natural", floating) do
    [
      "text-black dark:text-white [&_.password-field-wrapper:not(:has(.password-field-error))]:bg-natural-light",
      "dark:[&_.password-field-wrapper:not(:has(.password-field-error))]:bg-natural-dark",
      "[&_.password-field-wrapper.password-field-error]:bg-rose-700",
      "[&_.password-field-wrapper>input]:placeholder:text-white dark:[&_.password-field-wrapper>input]:placeholder:text-black",
      "[&_.password-field-wrapper>input]:text-white dark:[&_.password-field-wrapper>input]:text-black",
      "focus-within:[&_.password-field-wrapper]:ring-natural-light dark:focus-within:[&_.password-field-wrapper]:ring-natural-dark",
      "[&_.password-field-wrapper]:shadow-[0px_4px_6px_-4px_var(--color-shadow-natural)] [&_.password-field-wrapper]:shadow-[0px_10px_15px_-3px_var(--color-shadow-natural)]",
      "dark:[&_.password-field-wrapper]:shadow-none",
      floating == "outer" &&
        "[&_.password-field-wrapper_.floating-label]:bg-natural-light dark:[&_.password-field-wrapper_.floating-label]:bg-natural-dark"
    ]
  end

  defp color_variant("shadow", "primary", floating) do
    [
      "text-black dark:text-white [&_.password-field-wrapper:not(:has(.password-field-error))]:bg-primary-light",
      "dark:[&_.password-field-wrapper:not(:has(.password-field-error))]:bg-primary-dark",
      "[&_.password-field-wrapper.password-field-error]:bg-rose-700",
      "[&_.password-field-wrapper>input]:placeholder:text-white dark:[&_.password-field-wrapper>input]:placeholder:text-black",
      "[&_.password-field-wrapper>input]:text-white dark:[&_.password-field-wrapper>input]:text-black",
      "focus-within:[&_.password-field-wrapper]:ring-primary-light dark:focus-within:[&_.password-field-wrapper]:ring-primary-dark",
      "[&_.password-field-wrapper]:shadow-[0px_4px_6px_-4px_var(--color-shadow-primary)] [&_.password-field-wrapper]:shadow-[0px_10px_15px_-3px_var(--color-shadow-primary)]",
      "dark:[&_.password-field-wrapper]:shadow-none",
      floating == "outer" &&
        "[&_.password-field-wrapper_.floating-label]:bg-primary-light dark:[&_.password-field-wrapper_.floating-label]:bg-primary-dark"
    ]
  end

  defp color_variant("shadow", "secondary", floating) do
    [
      "text-black dark:text-white [&_.password-field-wrapper:not(:has(.password-field-error))]:bg-secondary-light",
      "dark:[&_.password-field-wrapper:not(:has(.password-field-error))]:bg-secondary-dark",
      "[&_.password-field-wrapper.password-field-error]:bg-rose-700",
      "[&_.password-field-wrapper>input]:placeholder:text-white dark:[&_.password-field-wrapper>input]:placeholder:text-black",
      "[&_.password-field-wrapper>input]:text-white dark:[&_.password-field-wrapper>input]:text-black",
      "focus-within:[&_.password-field-wrapper]:ring-secondary-light dark:focus-within:[&_.password-field-wrapper]:ring-secondary-dark",
      "[&_.password-field-wrapper]:shadow-[0px_4px_6px_-4px_var(--color-shadow-secondary)] [&_.password-field-wrapper]:shadow-[0px_10px_15px_-3px_var(--color-shadow-secondary)]",
      "dark:[&_.password-field-wrapper]:shadow-none",
      floating == "outer" &&
        "[&_.password-field-wrapper_.floating-label]:bg-secondary-light dark:[&_.password-field-wrapper_.floating-label]:bg-secondary-dark"
    ]
  end

  defp color_variant("shadow", "success", floating) do
    [
      "text-black dark:text-white [&_.password-field-wrapper:not(:has(.password-field-error))]:bg-success-light",
      "dark:[&_.password-field-wrapper:not(:has(.password-field-error))]:bg-success-dark",
      "[&_.password-field-wrapper.password-field-error]:bg-rose-700",
      "[&_.password-field-wrapper>input]:placeholder:text-white dark:[&_.password-field-wrapper>input]:placeholder:text-black",
      "[&_.password-field-wrapper>input]:text-white dark:[&_.password-field-wrapper>input]:text-black",
      "focus-within:[&_.password-field-wrapper]:ring-success-light dark:focus-within:[&_.password-field-wrapper]:ring-success-dark",
      "[&_.password-field-wrapper]:shadow-[0px_4px_6px_-4px_var(--color-shadow-success)] [&_.password-field-wrapper]:shadow-[0px_10px_15px_-3px_var(--color-shadow-success)]",
      "dark:[&_.password-field-wrapper]:shadow-none",
      floating == "outer" &&
        "[&_.password-field-wrapper_.floating-label]:bg-success-light dark:[&_.password-field-wrapper_.floating-label]:bg-success-dark"
    ]
  end

  defp color_variant("shadow", "warning", floating) do
    [
      "text-black dark:text-white [&_.password-field-wrapper:not(:has(.password-field-error))]:bg-warning-light",
      "dark:[&_.password-field-wrapper:not(:has(.password-field-error))]:bg-warning-dark",
      "[&_.password-field-wrapper.password-field-error]:bg-rose-700",
      "[&_.password-field-wrapper>input]:placeholder:text-white dark:[&_.password-field-wrapper>input]:placeholder:text-black",
      "[&_.password-field-wrapper>input]:text-white dark:[&_.password-field-wrapper>input]:text-black",
      "focus-within:[&_.password-field-wrapper]:ring-warning-light dark:focus-within:[&_.password-field-wrapper]:ring-warning-dark",
      "[&_.password-field-wrapper]:shadow-[0px_4px_6px_-4px_var(--color-shadow-warning)] [&_.password-field-wrapper]:shadow-[0px_10px_15px_-3px_var(--color-shadow-warning)]",
      "dark:[&_.password-field-wrapper]:shadow-none",
      floating == "outer" &&
        "[&_.password-field-wrapper_.floating-label]:bg-warning-light dark:[&_.password-field-wrapper_.floating-label]:bg-warning-dark"
    ]
  end

  defp color_variant("shadow", "danger", floating) do
    [
      "text-black dark:text-white [&_.password-field-wrapper:not(:has(.password-field-error))]:bg-danger-light",
      "dark:[&_.password-field-wrapper:not(:has(.password-field-error))]:bg-danger-dark",
      "[&_.password-field-wrapper.password-field-error]:bg-rose-700",
      "[&_.password-field-wrapper>input]:placeholder:text-white dark:[&_.password-field-wrapper>input]:placeholder:text-black",
      "[&_.password-field-wrapper>input]:text-white dark:[&_.password-field-wrapper>input]:text-black",
      "focus-within:[&_.password-field-wrapper]:ring-danger-light dark:focus-within:[&_.password-field-wrapper]:ring-danger-dark",
      "[&_.password-field-wrapper]:shadow-[0px_4px_6px_-4px_var(--color-shadow-danger)] [&_.password-field-wrapper]:shadow-[0px_10px_15px_-3px_var(--color-shadow-danger)]",
      "dark:[&_.password-field-wrapper]:shadow-none",
      floating == "outer" &&
        "[&_.password-field-wrapper_.floating-label]:bg-danger-light dark:[&_.password-field-wrapper_.floating-label]:bg-danger-dark"
    ]
  end

  defp color_variant("shadow", "info", floating) do
    [
      "text-black dark:text-white [&_.password-field-wrapper:not(:has(.password-field-error))]:bg-info-light",
      "dark:[&_.password-field-wrapper:not(:has(.password-field-error))]:bg-info-dark",
      "[&_.password-field-wrapper.password-field-error]:bg-rose-700",
      "[&_.password-field-wrapper>input]:placeholder:text-white dark:[&_.password-field-wrapper>input]:placeholder:text-black",
      "[&_.password-field-wrapper>input]:text-white dark:[&_.password-field-wrapper>input]:text-black",
      "focus-within:[&_.password-field-wrapper]:ring-info-light dark:focus-within:[&_.password-field-wrapper]:ring-info-dark",
      "[&_.password-field-wrapper]:shadow-[0px_4px_6px_-4px_var(--color-shadow-info)] [&_.password-field-wrapper]:shadow-[0px_10px_15px_-3px_var(--color-shadow-info)]",
      "dark:[&_.password-field-wrapper]:shadow-none",
      floating == "outer" &&
        "[&_.password-field-wrapper_.floating-label]:bg-info-light dark:[&_.password-field-wrapper_.floating-label]:bg-info-dark"
    ]
  end

  defp color_variant("shadow", "silver", floating) do
    [
      "text-black dark:text-white [&_.password-field-wrapper:not(:has(.password-field-error))]:bg-silver-light",
      "dark:[&_.password-field-wrapper:not(:has(.password-field-error))]:bg-silver-dark",
      "[&_.password-field-wrapper.password-field-error]:bg-rose-700",
      "[&_.password-field-wrapper>input]:placeholder:text-white dark:[&_.password-field-wrapper>input]:placeholder:text-black",
      "[&_.password-field-wrapper>input]:text-white dark:[&_.password-field-wrapper>input]:text-black",
      "focus-within:[&_.password-field-wrapper]:ring-silver-light dark:focus-within:[&_.password-field-wrapper]:ring-silver-dark",
      "[&_.password-field-wrapper]:shadow-[0px_4px_6px_-4px_var(--color-shadow-silver)] [&_.password-field-wrapper]:shadow-[0px_10px_15px_-3px_var(--color-shadow-silver)]",
      "dark:[&_.password-field-wrapper]:shadow-none",
      floating == "outer" &&
        "[&_.password-field-wrapper_.floating-label]:bg-silver-light dark:[&_.password-field-wrapper_.floating-label]:bg-silver-dark"
    ]
  end

  defp color_variant("transparent", "natural", _) do
    [
      "text-natural-light dark:text-natural-dark",
      "[&_.password-field-wrapper>input]:placeholder:text-natural-light",
      "dark:[&_.password-field-wrapper>input]:placeholder:text-natural-dark",
      "focus-within:[&_.password-field-wrapper]:ring-transparent"
    ]
  end

  defp color_variant("transparent", "primary", _) do
    [
      "text-primary-light dark:text-primary-dark",
      "[&_.password-field-wrapper>input]:placeholder:text-primary-light",
      "dark:[&_.password-field-wrapper>input]:placeholder:text-primary-dark",
      "focus-within:[&_.password-field-wrapper]:ring-transparent"
    ]
  end

  defp color_variant("transparent", "secondary", _) do
    [
      "text-secondary-light dark:text-secondary-dark",
      "[&_.password-field-wrapper>input]:placeholder:text-secondary-light",
      "dark:[&_.password-field-wrapper>input]:placeholder:text-secondary-dark",
      "focus-within:[&_.password-field-wrapper]:ring-transparent"
    ]
  end

  defp color_variant("transparent", "success", _) do
    [
      "text-success-light dark:text-success-dark",
      "[&_.password-field-wrapper>input]:placeholder:text-success-light",
      "dark:[&_.password-field-wrapper>input]:placeholder:text-success-dark",
      "focus-within:[&_.password-field-wrapper]:ring-transparent"
    ]
  end

  defp color_variant("transparent", "warning", _) do
    [
      "text-warning-light dark:text-warning-dark",
      "[&_.password-field-wrapper>input]:placeholder:text-warning-light",
      "dark:[&_.password-field-wrapper>input]:placeholder:text-warning-dark",
      "focus-within:[&_.password-field-wrapper]:ring-transparent"
    ]
  end

  defp color_variant("transparent", "danger", _) do
    [
      "text-danger-light dark:text-danger-dark",
      "[&_.password-field-wrapper>input]:placeholder:text-danger-light",
      "dark:[&_.password-field-wrapper>input]:placeholder:text-danger-dark",
      "focus-within:[&_.password-field-wrapper]:ring-transparent"
    ]
  end

  defp color_variant("transparent", "info", _) do
    [
      "text-info-light dark:text-info-dark",
      "[&_.password-field-wrapper>input]:placeholder:text-info-light",
      "dark:[&_.password-field-wrapper>input]:placeholder:text-info-dark",
      "focus-within:[&_.password-field-wrapper]:ring-transparent"
    ]
  end

  defp color_variant("transparent", "silver", _) do
    [
      "text-silver-light dark:text-silver-dark",
      "[&_.password-field-wrapper>input]:placeholder:text-silver-light",
      "dark:[&_.password-field-wrapper>input]:placeholder:text-silver-dark",
      "focus-within:[&_.password-field-wrapper]:ring-transparent"
    ]
  end

  defp color_variant(params, _, _) when is_binary(params), do: params

  defp translate_error({msg, opts}) do
    if count = opts[:count] do
      Gettext.dngettext(BasaWeb.Gettext, "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(BasaWeb.Gettext, "errors", msg, opts)
    end
  end
end
