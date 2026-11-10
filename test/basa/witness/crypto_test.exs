defmodule Basa.Witness.CryptoTest do
  use ExUnit.Case, async: true

  alias Basa.Witness.Crypto

  @vectors "spec/vectors/witness.json" |> File.read!() |> Jason.decode!()

  defp unhex(s), do: Base.decode16!(s, case: :lower)

  defp manifest(v) do
    m = v["manifest"]
    [lat, lon] = m["geo"]

    %{
      transaction_id: m["transaction_id"],
      contract_type: m["contract_type"],
      template: m["template"],
      jurisdiction: m["jurisdiction"],
      consumer: m["consumer"],
      parties:
        for(
          p <- m["parties"],
          do: %{role: p["role"], user_id: p["user_id"], public_key: unhex(p["public_key"])}
        ),
      files:
        for(
          f <- m["files"],
          do: %{
            sha256: Crypto.hash(f["content"]),
            kind: f["kind"],
            size: f["size"],
            media_type: f["media_type"]
          }
        ),
      created_at: m["created_at"],
      geo: {lat, lon}
    }
  end

  describe "test vectors (spec/vectors/witness.json)" do
    test "manifest bytes, BASA-HASH and its text form" do
      for f <- @vectors["manifest"]["files"],
          do: assert(Crypto.hash(f["content"]) == unhex(f["sha256"]))

      assert {:ok, cbor} = Crypto.encode_manifest(manifest(@vectors))
      assert cbor == unhex(@vectors["manifest_cbor"])
      assert Crypto.basa_hash(cbor) == unhex(@vectors["basa_hash"])
      assert Crypto.to_text(Crypto.basa_hash(cbor)) == @vectors["basa_hash_text"]
      assert Crypto.from_text(@vectors["basa_hash_text"]) == {:ok, unhex(@vectors["basa_hash"])}

      assert {:ok, decoded} = Crypto.decode_manifest(cbor)
      assert decoded.merkle_root == unhex(@vectors["merkle_root"])
      assert decoded.parties == manifest(@vectors).parties
    end

    test "Merkle proofs show each file alone" do
      hashes = for f <- @vectors["manifest"]["files"], do: unhex(f["sha256"])
      root = unhex(@vectors["merkle_root"])
      assert Crypto.merkle_root(hashes) == {:ok, root}

      for {proof, i} <- Enum.with_index(@vectors["merkle_proofs"]) do
        proof = Enum.map(proof, &unhex/1)
        assert Crypto.merkle_proof(hashes, i) == {:ok, proof}
        assert Crypto.merkle_verify(root, Enum.at(hashes, i), i, 3, proof)
        refute Crypto.merkle_verify(root, Crypto.hash("another file"), i, 3, proof)
      end
    end

    test "party signatures are reproducible and checked" do
      h = unhex(@vectors["basa_hash"])

      for s <- @vectors["signatures"] do
        party = Enum.find(manifest(@vectors).parties, &(&1.role == s["role"]))
        assert Crypto.sign_seal(unhex(s["private_key"]), h) == {:ok, unhex(s["signature"])}
        assert Crypto.verify_seal(party.public_key, h, unhex(s["signature"]))
        refute Crypto.verify_seal(party.public_key, Crypto.hash("other"), unhex(s["signature"]))
      end
    end

    test "every pair of shares and the recovery key give the data key" do
      d = @vectors["data_key"]
      key = unhex(d["key"])
      shares = Map.new(d["shares"], fn {k, v} -> {k, unhex(v)} end)

      for pair <- [~w(offeror acceptor), ~w(offeror basa), ~w(acceptor basa)] do
        assert Crypto.combine(Enum.map(pair, &shares[&1])) == {:ok, key}
      end

      assert {:error, _} = Crypto.combine([shares["basa"]])

      tx = @vectors["manifest"]["transaction_id"]

      assert Crypto.recover(unhex(d["recovery_private_key"]), unhex(d["recovery_sealed"]), tx) ==
               {:ok, key}

      contract = hd(@vectors["manifest"]["files"])

      assert Crypto.decrypt(key, unhex(d["contract_sealed"]), unhex(contract["sha256"])) ==
               {:ok, contract["content"]}
    end
  end

  describe "the round trip on every save" do
    setup do
      {recovery_private, recovery_public} = Crypto.recovery_keypair()
      {:ok, key} = Crypto.new_key("tx-1", recovery_public)
      %{key: key, recovery_private: recovery_private}
    end

    test "passes with all three pairs and the recovery key", %{key: key, recovery_private: sk} do
      assert Crypto.key_check(key, "a photo", recovery_private_key: sk, transaction_id: "tx-1") ==
               :ok

      assert Crypto.key_check(key, "a photo") == :ok
    end

    test "names what is broken", %{key: key, recovery_private: sk} do
      {_, other_public} = Crypto.recovery_keypair()
      {:ok, other} = Crypto.new_key("tx-1", other_public)

      broken = %{key | shares: %{key.shares | basa: other.shares.basa}, recovery: other.recovery}

      assert {:error, failures} =
               Crypto.key_check(broken, "a photo",
                 recovery_private_key: sk,
                 transaction_id: "tx-1"
               )

      assert :offeror_basa in failures and :acceptor_basa in failures and :recovery in failures
      refute :offeror_acceptor in failures

      assert {:error, [:recovery]} =
               Crypto.key_check(key, "a photo", recovery_private_key: sk, transaction_id: "tx-2")
    end
  end

  test "a changed manifest or a bad text form is refused" do
    {:ok, cbor} = Crypto.encode_manifest(manifest(@vectors))
    root = unhex(@vectors["merkle_root"])
    [before, rest] = :binary.split(cbor, root)
    <<first, tail::binary>> = root

    assert {:error, "Merkle root does not match the files"} =
             Crypto.decode_manifest(before <> <<Bitwise.bxor(first, 1)>> <> tail <> rest)

    assert {:error, _} = Crypto.encode_manifest(%{manifest(@vectors) | contract_type: "gift"})
    assert Crypto.from_text("basa0:not-base32!") == :error
    assert Crypto.from_text("mem1:" <> String.duplicate("a", 52)) == :error
  end
end
