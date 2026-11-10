defmodule Basa.Witness.MemAttestTest do
  use BasaWeb.ConnCase, async: true

  import Basa.WitnessFixtures
  import Basa.MemFixtures

  alias Basa.Witness
  alias Basa.Witness.{MemAttest, Native}

  @vectors "spec/vectors/mem-attest.json" |> File.read!() |> Jason.decode!()

  defp hex(key), do: Base.decode16!(@vectors[key], case: :lower)

  defp mem_phone(seed, origin) do
    prk = :crypto.mac(:hmac, :sha256, <<0::256>>, seed)
    okm = :crypto.mac(:hmac, :sha256, prk, "MEM/v1/attest-key" <> origin <> <<1>>)
    {public, private} = :crypto.generate_key(:eddsa, :ed25519, okm)
    %{public: public, private: private}
  end

  describe "MEM's published vectors" do
    test "BASA builds the same request" do
      {:ok, cbor} =
        Native.mem_request(
          "https://basa.ua",
          :binary.copy(<<7>>, 32),
          "basa0:abcdefgh",
          "offeror",
          :binary.copy(<<0x11>>, 16),
          "https://basa.ua/mem/attest"
        )

      assert "memattreq1:" <> Base.url_encode64(cbor, padding: false) == @vectors["request_a"]
    end

    test "BASA verifies MEM's attestations and rejects tampered ones" do
      {:ok, a} = Native.mem_verify(hex("attestation_a"))
      assert a.signer == hex("attest_pk_a")
      assert a.statement == hex("statement")
      assert a.origin == "https://basa.ua"
      {:ok, b} = Native.mem_verify(hex("attestation_b"))
      assert b.statement == a.statement

      bytes = hex("attestation_a")

      flipped =
        :binary.part(bytes, 0, byte_size(bytes) - 1) <> <<:binary.last(bytes) |> Bitwise.bxor(1)>>

      assert {:error, "bad signature"} = Native.mem_verify(flipped)
      assert {:error, _} = Native.mem_verify("not cbor")
    end

    test "the test phones sign exactly as MEM does" do
      phone = mem_phone(hex("identity_seed_a"), "https://basa.ua")
      assert phone.public == hex("attest_pk_a")
      assert sign(hex("statement"), :binary.copy(<<0x11>>, 16), phone) == hex("attestation_a")
    end
  end

  describe "BASA as the relying party" do
    setup do
      ctx = sealed_contract()
      {:ok, o} = Witness.issue_mem_attestation(ctx.tx.id, actor: ctx.lessor)
      {:ok, a} = Witness.issue_mem_attestation(ctx.tx.id, actor: ctx.lessee)

      requests = %{
        "offeror" => %{challenge: o.challenge, phone: phone()},
        "acceptor" => %{challenge: a.challenge, phone: phone()}
      }

      %{ctx: ctx, o: o, a: a, requests: requests}
    end

    test "both phones post; the contract is confirmed in person", %{
      ctx: ctx,
      o: o,
      a: a,
      requests: requests
    } do
      assert o.role == :offeror and a.role == :acceptor
      text = MemAttest.request_text(o, ctx.tx)
      assert "memattreq1:" <> _ = text

      {bo, ba} = attest_pair(MemAttest.origin(), ctx.tx.basa_hash, requests)
      assert post_cbor(MemAttest.submit_url(o), bo).status == 201
      refute Ash.reload!(ctx.tx, authorize?: false).mem_confirmed_at
      assert post_cbor(MemAttest.submit_url(a), ba).status == 201

      assert Ash.reload!(ctx.tx, authorize?: false).mem_confirmed_at
      assert {%{role: :offeror}, %{role: :acceptor}} = MemAttest.confirmed_pair(ctx.tx)
      assert post_cbor(MemAttest.submit_url(o), bo).status == 404
    end

    test "a shared file's package carries the confirmation, and /verify checks it", %{
      ctx: ctx,
      o: o,
      a: a,
      requests: requests
    } do
      tx = Ash.reload!(ctx.tx, authorize?: false)
      {:ok, before} = Basa.Witness.Disclosure.build(tx, [0])
      assert before["mem_attestations"] == []

      {bo, ba} = attest_pair(MemAttest.origin(), ctx.tx.basa_hash, requests)
      {:ok, _} = Witness.receive_mem_attestation(o, bo, :paste, actor: ctx.lessor)
      {:ok, _} = Witness.receive_mem_attestation(a, ba, :paste, actor: ctx.lessee)

      tx = Ash.reload!(ctx.tx, authorize?: false)
      assert {:in_person, :ok} in Basa.Witness.Verify.transaction(tx).checks
      {:ok, pkg} = Basa.Witness.Disclosure.build(tx, [0])
      assert length(pkg["mem_attestations"]) == 2
      result = pkg |> Jason.encode!() |> Basa.Witness.Disclosure.check_json()
      assert result.ok?
      assert {:in_person, :ok} in result.checks

      swapped = Map.update!(pkg, "mem_attestations", &Enum.reverse/1)
      result = Basa.Witness.Disclosure.check(swapped)
      refute result.ok?
      assert {:in_person, {:error, :mismatch}} in result.checks
    end

    test "attestations about something else are refused", %{ctx: ctx, o: o, requests: requests} do
      for opts <- [
            [subject: :binary.copy(<<1>>, 32)],
            [origin: "https://evil.example"],
            [roles: ["acceptor", "offeror"]]
          ] do
        {bo, _} = attest_pair(MemAttest.origin(), ctx.tx.basa_hash, requests, opts)
        assert post_cbor(MemAttest.submit_url(o), bo).status == 422
      end

      {bo, _} =
        attest_pair(
          MemAttest.origin(),
          ctx.tx.basa_hash,
          put_in(requests["offeror"].challenge, :crypto.strong_rand_bytes(16))
        )

      assert post_cbor(MemAttest.submit_url(o), bo).status == 422
      assert post_cbor(MemAttest.submit_url(o), "garbage").status == 422
      assert post_cbor("/mem/attest/AAAAAAAAAAAAAAAAAAAAAA", bo).status == 404
      assert post_cbor("/mem/attest/nope", bo).status == 404
      refute Ash.reload!(ctx.tx, authorize?: false).mem_confirmed_at
    end

    test "a code older than 15 minutes is refused", %{ctx: ctx, o: o, requests: requests} do
      {bo, _} = attest_pair(MemAttest.origin(), ctx.tx.basa_hash, requests)
      later = DateTime.add(o.inserted_at, 16, :minute)
      assert {:error, :expired} = MemAttest.check(o, ctx.tx, bo, later)
    end

    test "only the parties get codes, only for a sealed contract", %{ctx: ctx} do
      stranger = Basa.Fixtures.user()
      assert {:error, _} = Witness.issue_mem_attestation(ctx.tx.id, actor: stranger)
    end

    test "a pasted code works like a posted one; the other party cannot paste mine", %{
      ctx: ctx,
      o: o,
      requests: requests
    } do
      {bo, _} = attest_pair(MemAttest.origin(), ctx.tx.basa_hash, requests)
      {:ok, bytes} = MemAttest.from_text("Here: " <> text_form(bo) <> " thanks")
      assert bytes == bo
      assert {:error, _} = Witness.receive_mem_attestation(o, bytes, :paste, actor: ctx.lessee)

      assert {:ok, %{status: :received, via: :paste}} =
               Witness.receive_mem_attestation(o, bytes, :paste, actor: ctx.lessor)
    end
  end

  defp post_cbor(url, body) do
    path = URI.parse(url).path

    build_conn()
    |> Plug.Conn.put_req_header("content-type", "application/cbor")
    |> post(path, body)
  end
end
