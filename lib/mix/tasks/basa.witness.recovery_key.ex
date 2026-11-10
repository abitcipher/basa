defmodule Mix.Tasks.Basa.Witness.RecoveryKey do
  @shortdoc "Key ceremony: makes the witness recovery key and splits it in three"

  use Mix.Task

  @impl true
  def run(_args) do
    Mix.Task.run("loadpaths")
    Mix.Task.run("compile")

    {private, public} = Basa.Witness.Crypto.recovery_keypair()
    {:ok, parts} = Basa.Witness.Recovery.split_key(private)
    hex = &Base.encode16(&1, case: :lower)

    Mix.shell().info("""
    Witness recovery key

    Public key (WITNESS_RECOVERY_PUBLIC_KEY on the server):
      #{hex.(public)}

    Private key parts: give one to each holder; any two open a recovery kit.
    #{parts |> Enum.with_index(1) |> Enum.map_join("\n", fn {p, i} -> "  holder #{i}: #{hex.(p)}" end)}

    Clear this screen and the terminal history when the parts are written down.
    """)
  end
end
