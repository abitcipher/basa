defmodule Basa.Accounts.UiPrefs do
  @colours ~w(cyan green yellow orange)

  @choices %{
    "style" => ~w(brand black white),
    "action" => @colours,
    "nav" => ["neutral" | @colours],
    "disabled" => ~w(tint gray)
  }

  @scales %{"button" => {80, 130}, "icon" => {80, 150}, "text" => {85, 130}}

  @defaults %{
    "style" => "brand",
    "action" => "cyan",
    "nav" => "neutral",
    "disabled" => "tint",
    "button" => 100,
    "icon" => 100,
    "text" => 100
  }

  def defaults, do: @defaults
  def choices, do: @choices
  def scales, do: @scales

  def normalize(prefs) when is_map(prefs) do
    prefs = Map.new(prefs, fn {k, v} -> {to_string(k), v} end)

    choice =
      for {key, allowed} <- @choices,
          value = to_string(prefs[key] || ""),
          value in allowed,
          into: %{} do
        {key, value}
      end

    scale =
      for {key, {lo, hi}} <- @scales, n = integer(prefs[key]), n != nil, into: %{} do
        {key, n |> max(lo) |> min(hi)}
      end

    Map.merge(choice, scale)
  end

  def normalize(_), do: %{}

  def get(%{ui: ui}) when is_map(ui), do: Map.merge(@defaults, normalize(ui))
  def get(_), do: @defaults

  def html_attrs(user) do
    p = get(user)

    [
      {"data-btn-style", p["style"]},
      {"data-btn-action", p["action"]},
      {"data-btn-nav", p["nav"]},
      {"data-btn-disabled", p["disabled"]},
      {"style",
       "--ui-btn-scale:#{p["button"] / 100};--ui-icon-scale:#{p["icon"] / 100};--ui-btn-text:#{p["text"] / 100}"}
    ]
  end

  defp integer(n) when is_integer(n), do: n

  defp integer(s) when is_binary(s) do
    case Integer.parse(s) do
      {n, _} -> n
      :error -> nil
    end
  end

  defp integer(_), do: nil
end
