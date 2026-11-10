defmodule Mix.Tasks.Basa.Render.Build do
  @shortdoc "Builds basa-render (native/render) into priv/native"

  use Mix.Task

  @crate "native/render"
  @target "priv/native/basa-render"

  @impl true
  def run(_args) do
    cond do
      System.get_env("BASA_SKIP_RENDER") in ["1", "true"] ->
        :ok

      System.find_executable("cargo") == nil ->
        :ok

      true ->
        build()
    end
  end

  defp build do
    case System.cmd("cargo", ["build", "--release", "--quiet"],
           cd: @crate,
           stderr_to_stdout: true
         ) do
      {_, 0} ->
        built = Path.join([@crate, "target", "release", "basa-render"])
        File.mkdir_p!(Path.dirname(@target))

        unless File.exists?(@target) and File.stat!(@target).mtime >= File.stat!(built).mtime do
          File.cp!(built, @target)
          File.chmod!(@target, 0o755)
          Mix.shell().info("Built #{@target}")
        end

        :ok

      {output, _} ->
        Mix.shell().error("basa-render did not build:\n" <> output)
        :ok
    end
  end
end
