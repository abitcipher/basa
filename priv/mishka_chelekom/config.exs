
import Config

config :mishka_chelekom,
  component_prefix: nil,

  module_prefix: nil,

  exclude_components: ["device_mockup", "mega_menu", "carousel", "gallery", "video", "jumbotron", "keyboard", "speed_dial", "table_content", "banner", "color_field"],


  component_colors: ["base", "natural", "white", "dark", "primary", "secondary", "success", "warning", "danger", "info", "silver"],

  component_variants: [],

  component_sizes: [],

  component_rounded: [],

  component_padding: [],

  component_space: [],

  css_overrides:
    %{
      primary_light: "#007ea3",
      primary_dark: "#33d6ff",
      primary_hover_light: "#006685",
      primary_hover_dark: "#80e6ff",
      primary_bordered_text_light: "#006685",
      primary_bordered_text_dark: "#80e6ff",
      primary_bordered_bg_light: "#e6f9ff",
      primary_bordered_bg_dark: "#00303d",
      primary_bordered_hover_light: "#d1f3ff",
      primary_bordered_hover_dark: "#00404f",
      primary_indicator_light: "#00546e",
      primary_indicator_dark: "#b3efff",
      primary_border_light: "#00546e",
      primary_border_dark: "#b3efff",
      primary_gradient_indicator_dark: "#d9f6ff",
      secondary_light: "#c2510a",
      secondary_dark: "#ff9a57",
      secondary_hover_light: "#a04308",
      secondary_hover_dark: "#ffbf94",
      secondary_bordered_text_light: "#a04308",
      secondary_bordered_text_dark: "#ffbf94",
      secondary_bordered_bg_light: "#fff2ea",
      secondary_bordered_bg_dark: "#3a1a05",
      secondary_bordered_hover_light: "#ffe4d3",
      secondary_bordered_hover_dark: "#4f2408",
      secondary_indicator_light: "#8a3a07",
      secondary_indicator_dark: "#ffd2b3",
      secondary_border_light: "#8a3a07",
      secondary_border_dark: "#ffd2b3",
      secondary_gradient_indicator_dark: "#ffe6d5",
      success_light: "#0b7a1e",
      success_dark: "#3ee05a",
      success_hover_light: "#086418",
      success_hover_dark: "#8eeb9c",
      success_bordered_text_light: "#086418",
      success_bordered_text_dark: "#8eeb9c",
      success_bordered_bg_light: "#e8fbe8",
      success_bordered_bg_dark: "#002b08",
      success_bordered_hover_light: "#d6f7d6",
      success_bordered_hover_dark: "#013d0c",
      success_indicator_light: "#0a6b1a",
      success_indicator_alt_light: "#075214",
      success_indicator_dark: "#b9f3c2",
      success_border_light: "#075214",
      success_border_dark: "#b9f3c2",
      success_gradient_indicator_dark: "#dcf9dc",
      warning_light: "#8a6600",
      warning_dark: "#ffd42a",
      warning_hover_light: "#6e5100",
      warning_hover_dark: "#ffe07a",
      warning_bordered_text_light: "#6e5100",
      warning_bordered_text_dark: "#ffe07a",
      warning_bordered_bg_light: "#fff9e0",
      warning_bordered_bg_dark: "#332800",
      warning_bordered_hover_light: "#fff2c2",
      warning_bordered_hover_dark: "#4a3a00",
      warning_indicator_light: "#ff7f2a",
      warning_indicator_alt_light: "#5c4400",
      warning_indicator_dark: "#ffe9a3",
      warning_border_light: "#5c4400",
      warning_border_dark: "#ffe9a3",
      warning_gradient_indicator_dark: "#fff4c7",


















    },

  css_merge_strategy: :merge,

  custom_css_path: nil
