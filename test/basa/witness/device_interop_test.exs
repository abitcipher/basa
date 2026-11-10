defmodule Basa.Witness.DeviceInteropTest do
  use ExUnit.Case, async: true

  @widgets Path.expand("../../../assets/widgets", __DIR__)

  @tag :interop
  test "the browser code opens a device seal made by the Rust core" do
    node = System.find_executable("node")

    if node && File.dir?(Path.join(@widgets, "node_modules/@hpke/core")) do
      {out, status} =
        System.cmd(node, ["test/device_seal.mjs"], cd: @widgets, stderr_to_stdout: true)

      assert status == 0, out
      assert out =~ "ok:"
    else
      IO.puts("skipped: node or assets/widgets/node_modules missing")
    end
  end

  test "the vector opens in Elixir too" do
    v =
      "spec/vectors/witness.json" |> File.read!() |> Jason.decode!() |> Map.fetch!("device_seal")

    unhex = &Base.decode16!(&1, case: :lower)

    assert Basa.Witness.Crypto.open_for_device(
             unhex.(v["private_key"]),
             unhex.(v["sealed"]),
             v["aad"]
           ) ==
             {:ok, unhex.(v["plain"])}
  end
end
