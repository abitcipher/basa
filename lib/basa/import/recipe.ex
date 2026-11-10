defmodule Basa.Import.Recipe do
  alias Basa.Import.{Detect, Price, Selector}
  alias RulesEngine, as: Engine

  @fields Detect.fields()
  @field_names Map.new(@fields, &{Atom.to_string(&1), &1})

  @type t :: %{fields: %{atom() => Selector.rule()}, rules: map() | nil}

  @spec load(map()) :: t()
  def load(json) when is_map(json) do
    fields =
      for {name, rule} <- json["fields"] || %{},
          field = @field_names[to_string(name)],
          rule = rule(rule),
          into: %{},
          do: {field, rule}

    %{
      fields: fields,
      rules: if(is_map(json["rules"]) and json["rules"] != %{}, do: json["rules"])
    }
  end

  @spec dump(t()) :: map()
  def dump(%{fields: fields, rules: rules}) do
    %{
      "fields" =>
        Map.new(fields, fn {field, rule} ->
          {Atom.to_string(field),
           rule |> Map.new(fn {k, v} -> {Atom.to_string(k), dump_value(v)} end) |> drop_nil()}
        end),
      "rules" => rules
    }
  end

  defp dump_value(v) when is_atom(v) and not is_nil(v), do: Atom.to_string(v)
  defp dump_value(v), do: v
  defp drop_nil(map), do: map |> Enum.reject(fn {_, v} -> is_nil(v) end) |> Map.new()

  defp rule(%{"from" => "css", "selector" => s} = r) when is_binary(s) and s != "",
    do: %{from: :css, selector: s, attr: r["attr"]}

  defp rule(%{"from" => "spec", "label" => l}) when is_binary(l) and l != "",
    do: %{from: :spec, label: l}

  defp rule(%{from: _} = rule), do: rule
  defp rule(_), do: nil

  @spec apply(t(), map(), String.t()) :: {:ok, map()} | {:error, term()}
  def apply(recipe, %{html: html} = result, base_url) do
    doc = Floki.parse_document!(html)

    {fields, sources} =
      Enum.reduce(recipe.fields, {result.fields, result.sources}, fn {field, rule},
                                                                     {fields, sources} ->
        raw =
          if field == :photos,
            do: Selector.values(doc, rule),
            else: Selector.value(doc, rule, result.specs)

        case raw && Detect.clean_field(field, raw, base_url) do
          empty when empty in [nil, "", []] ->
            {fields, sources}

          value ->
            fields = Map.put(fields, field, value)

            fields =
              if field == :price and not Map.has_key?(recipe.fields, :currency),
                do: put_currency(fields, Price.currency(raw)),
                else: fields

            {fields, Map.put(sources, field, :recipe)}
        end
      end)

    result = %{result | fields: fields, sources: sources}

    case recipe.rules do
      nil -> {:ok, Map.merge(result, %{skip: false, attrs: %{}})}
      graph -> transform(graph, result, base_url)
    end
  end

  defp put_currency(fields, nil), do: fields
  defp put_currency(fields, currency), do: Map.put(fields, :currency, currency)

  defp transform(graph, result, base_url) do
    input = %{
      "fields" => jsonable(result.fields),
      "specs" => Map.new(result.specs),
      "url" => base_url
    }

    case Engine.evaluate(graph, input) do
      {:ok, output} ->
        {fields, sources} =
          Enum.reduce(output, {result.fields, result.sources}, fn {key, value},
                                                                  {fields, sources} ->
            case @field_names[key] do
              nil ->
                {fields, sources}

              _field when value in [nil, ""] ->
                {fields, sources}

              field ->
                {Map.put(
                   fields,
                   field,
                   Detect.clean_field(field, to_text(field, value), base_url)
                 ), Map.put(sources, field, :rules)}
            end
          end)

        {:ok,
         %{result | fields: fields, sources: sources}
         |> Map.put(:skip, output["skip"] == true)
         |> Map.put(:attrs, if(is_map(output["attrs"]), do: output["attrs"], else: %{}))}

      {:error, reason} ->
        {:error, {:rules, reason}}
    end
  end

  defp jsonable(fields) do
    Map.new(fields, fn
      {k, %Decimal{} = d} -> {Atom.to_string(k), Decimal.to_float(d)}
      {k, v} -> {Atom.to_string(k), v}
    end)
  end

  defp to_text(:photos, value), do: List.wrap(value)
  defp to_text(_field, value) when is_binary(value), do: value
  defp to_text(_field, value) when is_number(value), do: to_string(value)
  defp to_text(_field, value), do: inspect(value)
end
