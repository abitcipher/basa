defmodule Mix.Tasks.Basa.Witness.Verify do
  @shortdoc "Checks witness transactions: keys, files, manifest, signatures"

  use Mix.Task

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    results =
      case args do
        ["--all"] ->
          Basa.Witness.Verify.all(reason: "mix basa.witness.verify")

        [] ->
          Mix.raise("Give transaction ids, or --all")

        ids ->
          for id <- ids do
            tx = Basa.Witness.get_transaction!(id, authorize?: false)
            {id, Basa.Witness.Verify.transaction(tx, reason: "mix basa.witness.verify")}
          end
      end

    for {id, %{ok?: ok?, checks: checks}} <- results do
      Mix.shell().info("#{if ok?, do: "ok    ", else: "FAILED"} #{id}")

      for {name, result} <- checks, result != :ok do
        Mix.shell().error("         #{inspect(name)}: #{inspect(result)}")
      end
    end

    Mix.shell().info(
      "#{length(results)} checked, #{Enum.count(results, fn {_, r} -> not r.ok? end)} failed"
    )

    if Enum.any?(results, fn {_, r} -> not r.ok? end), do: exit({:shutdown, 1})
  end
end
