defmodule Mix.Tasks.Basa.Import.Detect do
  @shortdoc "Shows the listing fields BASA finds on a web page"

  use Mix.Task

  @impl true
  def run(args) do
    {opts, [url | _], _} =
      OptionParser.parse(args, strict: [insecure: :boolean, browser: :boolean])

    Mix.Task.run("app.start")

    case Basa.Import.detect(url,
           insecure: opts[:insecure] || false,
           browser: Keyword.get(opts, :browser, :auto)
         ) do
      {:ok, result} ->
        Mix.shell().info("read by: #{result.via}")

        for {field, value} <- result.fields do
          Mix.shell().info("#{field} (#{result.sources[field]}): #{show(value)}")
        end

        types =
          result.json_ld |> Enum.map(&inspect(&1["@type"])) |> Enum.uniq() |> Enum.join(", ")

        Mix.shell().info("JSON-LD types: #{if types == "", do: "none", else: types}")

        for s <- result.states do
          keys =
            if is_map(s.data),
              do: s.data |> Map.keys() |> Enum.take(12) |> Enum.join(", "),
              else: "list"

          Mix.shell().info("state #{s.name}: #{keys}")
        end

      {:error, reason} ->
        Mix.shell().error("Could not read the page: #{inspect(reason)}")
    end
  end

  defp show(list) when is_list(list),
    do: "#{length(list)}: " <> Enum.join(Enum.take(list, 3), " ")

  defp show(%Decimal{} = d), do: Decimal.to_string(d, :normal)
  defp show(s) when is_binary(s), do: String.slice(s, 0, 160)
  defp show(other), do: inspect(other)
end
