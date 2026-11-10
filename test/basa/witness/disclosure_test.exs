defmodule Basa.Witness.DisclosureTest do
  use Basa.DataCase, async: true

  import Basa.WitnessFixtures

  alias Basa.Witness.{Crypto, Disclosure}

  setup do
    ctx = sealed_contract(photos: ["photo one", "photo two"])
    {:ok, %{token: token, time: time}} = Basa.Witness.Timestamp.stamp(ctx.tx.basa_hash)

    tx =
      Ash.update!(ctx.tx, %{timestamp_token: token, timestamped_at: time},
        action: :record_timestamp,
        authorize?: false
      )

    %{ctx | tx: tx}
  end

  test "one file with its proof checks out, the others stay out", %{tx: tx} do
    {:ok, pkg} = Disclosure.build(tx, [1])
    assert [%{"index" => 1}] = pkg["files"]
    assert Base.decode64!(hd(pkg["files"])["content"]) == "photo two"

    result = pkg |> Jason.encode!() |> Disclosure.check_json()
    assert result.ok?
    assert result.basa_hash == Crypto.to_text(tx.basa_hash)
    assert result.time
    assert {{:signature, "offeror"}, :ok} in result.checks
    assert {{:file, 1}, :ok} in result.checks
  end

  test "changes are caught", %{tx: tx} do
    {:ok, pkg} = Disclosure.build(tx, [0])
    [file] = pkg["files"]

    changed = put_in(pkg, ["files"], [%{file | "content" => Base.encode64("another photo")}])
    assert {{:file, 0}, {:error, :content_differs}} in Disclosure.check(changed).checks

    moved = put_in(pkg, ["files"], [%{file | "index" => 1}])
    refute Disclosure.check(moved).ok?

    other = Disclosure.check(%{pkg | "basa_hash" => Crypto.to_text(Crypto.hash("x"))})
    assert {:basa_hash, {:error, :mismatch}} in other.checks

    unsigned = Disclosure.check(%{pkg | "signatures" => []})
    refute unsigned.ok?
    assert {{:signature, "acceptor"}, :missing} in unsigned.checks

    assert Disclosure.check_json("not json").checks == [{:package, {:error, :not_json}}]
  end

  test "a file from another contract does not fit this one", %{tx: tx} do
    other = sealed_contract(photos: ["someone else's photo"], hours: 60)
    {:ok, theirs} = Disclosure.build(other.tx, [0])
    {:ok, mine} = Disclosure.build(tx, [0])

    mixed = %{mine | "files" => theirs["files"]}
    refute Disclosure.check(mixed).ok?
  end
end
