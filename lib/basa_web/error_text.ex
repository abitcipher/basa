defmodule BasaWeb.ErrorText do
  def messages(%{errors: errors}) when is_list(errors), do: Enum.flat_map(errors, &messages/1)

  def messages(%{message: message} = error) when is_binary(message) do
    vars = error |> Map.get(:vars, []) |> Enum.map(fn {k, v} -> {k, to_string_safe(v)} end)

    text =
      try do
        Basa.I18n.t(message, vars)
      rescue
        _ -> Enum.reduce(vars, message, fn {k, v}, acc -> String.replace(acc, "%{#{k}}", v) end)
      end

    field = Map.get(error, :field) || Map.get(error, :fields, []) |> List.wrap() |> List.first()
    [if(field, do: "#{humanize(field)}: #{text}", else: text)]
  end

  def messages(error) when is_exception(error), do: [Exception.message(error)]
  def messages(other), do: [inspect(other)]

  defp humanize(field),
    do: field |> to_string() |> String.replace("_", " ") |> String.capitalize()

  defp to_string_safe(v) when is_list(v), do: Enum.map_join(v, ", ", &to_string_safe/1)
  defp to_string_safe(v), do: to_string(v)
end
