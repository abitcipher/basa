defmodule Basa.JsonSchema do
  def validate(schema, data) when schema in [nil, %{}], do: {:ok, stringify(data)}

  def validate(schema, data) do
    data = stringify(data)

    with {:ok, root} <- JSV.build(schema),
         {:ok, _} <- JSV.validate(data, root, cast: false) do
      {:ok, data}
    else
      {:error, %JSV.ValidationError{} = error} -> {:error, messages(error)}
      {:error, error} -> {:error, [Exception.message(error)]}
    end
  end

  def fields(schema, locale \\ nil)

  def fields(%{"properties" => props} = schema, locale) do
    required = Map.get(schema, "required", [])
    order = Map.get(schema, "x-order", Map.keys(props) |> Enum.sort())
    locale = to_string(locale || Gettext.get_locale(BasaWeb.Gettext))

    for name <- order, prop = props[name], prop != nil do
      %{
        name: name,
        label: get_in(prop, ["x-title", locale]) || prop["title"] || humanize(name),
        enum_labels: get_in(prop, ["x-enum-titles", locale]) || %{},
        type: field_type(prop),
        required?: name in required,
        enum: prop["enum"],
        min: prop["minimum"],
        max: prop["maximum"],
        step: if(prop["type"] == "integer", do: 1, else: prop["multipleOf"] || "any"),
        unit: prop["x-unit"],
        help: get_in(prop, ["x-description", locale]) || prop["description"]
      }
    end
  end

  def fields(_, _), do: []

  def cast_params(schema, params) when is_map(params) do
    props = Map.get(schema || %{}, "properties", %{})

    for {key, value} <- params,
        prop = props[key],
        prop != nil,
        value not in [nil, ""],
        into: %{} do
      {key, cast(prop["type"], value)}
    end
  end

  defp cast("integer", v) when is_binary(v), do: parse(Integer.parse(v), v)
  defp cast("number", v) when is_binary(v), do: parse(Float.parse(v), v)
  defp cast("boolean", v), do: v in [true, "true", "on", "1"]
  defp cast(_, v), do: v

  defp parse({n, ""}, _), do: n
  defp parse(_, v), do: v

  defp field_type(%{"enum" => _}), do: :select
  defp field_type(%{"type" => "boolean"}), do: :checkbox
  defp field_type(%{"type" => t}) when t in ["number", "integer"], do: :number
  defp field_type(%{"format" => "uri"}), do: :url
  defp field_type(_), do: :text

  defp humanize(name), do: name |> String.replace("_", " ") |> String.capitalize()

  defp stringify(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {to_string(k), v} end)
  end

  defp messages(error) do
    error
    |> JSV.normalize_error()
    |> collect_messages()
    |> case do
      [] -> ["is invalid"]
      list -> Enum.uniq(list)
    end
  end

  defp collect_messages(%{details: details}) when is_list(details),
    do: Enum.flat_map(details, &collect_messages/1)

  defp collect_messages(%{errors: errors} = unit) when is_list(errors) do
    location = Map.get(unit, :instanceLocation, "")

    Enum.flat_map(errors, fn
      %{message: message} -> [prefix(location, message)]
      other -> collect_messages(other)
    end)
  end

  defp collect_messages(%{valid: false} = unit), do: collect_messages(Map.delete(unit, :valid))
  defp collect_messages(_), do: []

  defp prefix(location, message) when location in ["", "#"], do: message
  defp prefix(location, message), do: "#{String.trim_leading(location, "#/")}: #{message}"
end
