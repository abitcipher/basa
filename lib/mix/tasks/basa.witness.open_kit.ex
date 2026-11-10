defmodule Mix.Tasks.Basa.Witness.OpenKit do
  @shortdoc "Opens a recovery kit offline with two parts of the recovery key"

  use Mix.Task

  alias Basa.Witness.Recovery

  @impl true
  def run(args) do
    Mix.Task.run("loadpaths")
    Mix.Task.run("compile")

    {opts, files, _} = OptionParser.parse(args, strict: [part: :keep, key: :string, out: :string])
    path = List.first(files) || Mix.raise("Give the kit file")
    kit = path |> File.read!() |> Jason.decode!()

    private =
      case {opts[:key], Keyword.get_values(opts, :part)} do
        {key, _} when is_binary(key) ->
          Base.decode16!(key, case: :mixed)

        {nil, parts} when length(parts) >= 2 ->
          case Recovery.combine_key(Enum.map(parts, &Base.decode16!(&1, case: :mixed))) do
            {:ok, key} -> key
            {:error, reason} -> Mix.raise("The parts do not fit together: #{inspect(reason)}")
          end

        _ ->
          Mix.raise("Give two key parts (--part HEX --part HEX)")
      end

    case Recovery.open_kit(kit, private) do
      {:ok, %{files: opened, report: report}} ->
        reference = kit["request"]["reference"] |> String.replace(~r/[^\w.-]+/u, "_")
        out = opts[:out] || "recovery-#{reference}"
        File.mkdir_p!(out)
        for f <- opened, do: File.write!(Path.join(out, f.name), f.content)
        {json, sha} = Recovery.report_json(report)
        File.write!(Path.join(out, "report.json"), json)

        bad = Enum.reject(report["files"], &(&1["result"] == "ok"))

        Mix.shell().info("""
        Opened #{length(opened)} of #{length(report["files"])} files into #{out}
        Contract authentic: #{report["contract"]["authentic"]}
        Report SHA-256 (record it in BASA): #{sha}
        """)

        for f <- bad, do: Mix.shell().error("  #{f["name"]}: #{f["result"]}")

      {:error, reason} ->
        Mix.raise("Cannot open the kit: #{inspect(reason)}")
    end
  end
end
