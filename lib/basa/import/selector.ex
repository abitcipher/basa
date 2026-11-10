defmodule Basa.Import.Selector do
  alias Basa.Import.Detect

  @type node_info :: %{
          required(:tag) => String.t(),
          optional(:id) => String.t() | nil,
          optional(:classes) => [String.t()],
          optional(:attrs) => %{optional(String.t()) => String.t()},
          optional(:nth) => pos_integer()
        }

  @type picked :: %{
          required(:chain) => [node_info()],
          optional(:text) => String.t(),
          optional(:src) => String.t()
        }

  @type rule ::
          %{from: :spec, label: String.t()}
          | %{from: :css, selector: String.t(), attr: String.t() | nil}

  @spec suggest(String.t() | Floki.html_tree(), picked()) :: [%{rule: rule(), value: String.t()}]
  def suggest(html, picked) when is_binary(html), do: suggest(Floki.parse_document!(html), picked)

  def suggest(doc, %{chain: chain} = picked) when chain != [] do
    element = List.last(chain)
    attr = value_attr(element, picked)
    wanted = wanted(picked, attr)

    specs =
      for {label, value} <- Detect.specs(doc),
          same?(value, wanted) or same?(value |> String.split("\n") |> hd(), wanted),
          do: %{rule: %{from: :spec, label: label}, value: value}

    css =
      element
      |> candidates(chain)
      |> Enum.uniq()
      |> Enum.flat_map(fn selector ->
        case Floki.find(doc, selector) do
          [found] ->
            value = value_of(found, attr)

            if same?(value, wanted),
              do: [%{rule: %{from: :css, selector: selector, attr: attr}, value: value}],
              else: []

          _ ->
            []
        end
      end)

    specs ++ css
  rescue
    _ -> []
  end

  def suggest(_doc, _picked), do: []

  @spec value(Floki.html_tree(), rule(), [{String.t(), String.t()}]) :: String.t() | nil
  def value(_doc, %{from: :spec, label: label}, specs) do
    down = String.downcase(label)
    Enum.find_value(specs, fn {l, v} -> if String.downcase(l) == down, do: v end)
  end

  def value(doc, %{from: :css, selector: selector} = rule, _specs) do
    case Floki.find(doc, selector) do
      [found | _] -> value_of(found, rule[:attr])
      [] -> nil
    end
  rescue
    _ -> nil
  end

  def values(doc, %{from: :css, selector: selector} = rule) do
    doc
    |> Floki.find(selector)
    |> Enum.map(&value_of(&1, rule[:attr]))
    |> Enum.reject(&(&1 in [nil, ""]))
  rescue
    _ -> []
  end

  def values(doc, rule), do: doc |> value(rule, []) |> List.wrap()

  defp candidates(element, chain) do
    tag = element.tag
    classes = stable_classes(element)
    attrs = element[:attrs] || %{}
    ancestors = Enum.drop(chain, -1)
    anchor = ancestors |> Enum.reverse() |> Enum.find(&stable_id?(&1[:id]))

    [
      stable_id?(element[:id]) && "##{css_ident(element.id)}",
      attrs["itemprop"] && ~s(#{tag}[itemprop="#{attrs["itemprop"]}"]),
      classes != [] && tag <> Enum.map_join(classes, &".#{css_ident(&1)}"),
      anchor && classes != [] &&
        "##{css_ident(anchor.id)} #{tag}" <> Enum.map_join(classes, &".#{css_ident(&1)}"),
      anchor && "##{css_ident(anchor.id)} " <> path(after_anchor(chain, anchor)),
      path(chain)
    ]
    |> Enum.filter(&is_binary/1)
  end

  defp after_anchor(chain, anchor) do
    index = Enum.find_index(chain, &(&1 == anchor))
    Enum.drop(chain, index + 1)
  end

  defp path(nodes) do
    {parts, _} =
      nodes
      |> Enum.reject(&(&1.tag == "html"))
      |> Enum.reduce({[], nil}, fn
        %{tag: "tbody"}, {parts, _} -> {parts, :skipped}
        node, {[], _} -> {[step(node)], nil}
        node, {parts, :skipped} -> {parts ++ [" ", step(node)], nil}
        node, {parts, _} -> {parts ++ [" > ", step(node)], nil}
      end)

    Enum.join(parts)
  end

  defp step(%{tag: tag} = node) when tag in ["body", "head"], do: node.tag
  defp step(%{tag: tag, nth: n}) when is_integer(n), do: "#{tag}:nth-of-type(#{n})"
  defp step(%{tag: tag}), do: tag

  defp stable_id?(id) when is_binary(id) and id != "",
    do: String.length(id) <= 40 and not (id =~ ~r/\d{3,}|^[a-f0-9-]{16,}$/i)

  defp stable_id?(_), do: false

  defp stable_classes(node) do
    (node[:classes] || [])
    |> Enum.reject(
      &(&1 =~ ~r/\d{3,}|^(css|sc|jsx|svelte)-|__[a-zA-Z0-9]{5,}$|^(active|hover|selected|open)$/)
    )
    |> Enum.take(2)
  end

  defp css_ident(name), do: String.replace(name, ~r/[^a-zA-Z0-9_-]/, &"\\#{&1}")

  defp value_attr(%{tag: tag}, picked) when tag in ["img", "source"] do
    if picked[:src], do: "src"
  end

  defp value_attr(_, _), do: nil

  defp wanted(picked, "src"), do: picked[:src]
  defp wanted(picked, _), do: picked[:text]

  defp value_of(node, "src") do
    ~w(data-src data-lazy-src data-original src)
    |> Enum.map(&(node |> Floki.attribute(&1) |> List.first()))
    |> Enum.find(&(&1 && not String.starts_with?(&1, "data:")))
  end

  defp value_of(node, nil), do: node |> Floki.text(sep: " ") |> Detect.text()
  defp value_of(node, attr), do: node |> Floki.attribute(attr) |> List.first()

  defp same?(a, b) when is_binary(a) and is_binary(b), do: norm(a) == norm(b) and norm(a) != ""
  defp same?(_, _), do: false

  defp norm(s),
    do: s |> String.replace(~r/\s+/u, " ") |> String.trim() |> String.trim_trailing(":")
end
