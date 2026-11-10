defmodule Basa.Witness.QESCscTest do
  use BasaWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Basa.WitnessFixtures

  alias Basa.Witness.{QualifiedSignature, Verify}
  alias BasaWeb.Dev.CscEmulator

  setup do
    old = Application.get_env(:basa, Basa.Witness.QES)
    Application.put_env(:basa, Basa.Witness.QES, providers: [:dev, :csc])
    on_exit(fn -> Application.put_env(:basa, Basa.Witness.QES, old) end)

    Req.Test.stub(Basa.Witness.QES.CscProvider, fn conn ->
      CscEmulator.call(conn, CscEmulator.init([]))
    end)

    %{ctx: sealed_contract()}
  end

  defp query(url), do: url |> URI.parse() |> Map.get(:query) |> URI.decode_query()

  defp start(ctx) do
    {:ok, view, _} = live(build_conn() |> sign_in(ctx.lessor), ~p"/transactions/#{ctx.tx.id}")

    {:error, {:redirect, %{to: url}}} = view |> element("#qes-start-csc") |> render_click()
    url
  end

  defp back(ctx, params) do
    path = URI.parse(params["redirect_uri"]).path
    build_conn() |> sign_in(ctx.lessor) |> get(path, Map.take(params, ["code", "state", "error"]))
  end

  defp approve(ctx, url, name \\ "Olena Kovalenko", tweak \\ & &1) do
    q = query(url) |> tweak.()
    back(ctx, Map.put(q, "code", CscEmulator.code(q, name)))
  end

  test "two authorizations at a CSC provider give a verified signature", %{ctx: ctx} do
    url = start(ctx)
    q = query(url)
    assert url =~ "http://csc.test/oauth2/authorize?"
    assert q["scope"] == "service" and q["code_challenge_method"] == "S256"

    conn = approve(ctx, url)
    second = redirected_to(conn)
    q2 = query(second)
    assert q2["scope"] == "credential"
    assert q2["numSignatures"] == "1"
    assert q2["hashAlgorithmOID"] == "2.16.840.1.101.3.4.2.1"
    assert q2["credentialID"] =~ "emu-"

    conn = approve(ctx, second)
    assert redirected_to(conn) == ~p"/transactions/#{ctx.tx.id}"
    assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "qualified signature was added"

    [signed] = Ash.read!(QualifiedSignature, authorize?: false)
    assert signed.status == :signed and signed.provider == :csc
    assert signed.subject == "Olena Kovalenko"
    assert signed.test
    tx = Ash.reload!(ctx.tx, authorize?: false)
    assert {{:qualified, :offeror}, :test} in Verify.transaction(tx).checks
  end

  test "a denied signing fails cleanly", %{ctx: ctx} do
    url = start(ctx)
    q = query(url)
    conn = back(ctx, Map.put(q, "error", "access_denied"))
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "cancelled"
    assert [%{status: :failed}] = Ash.read!(QualifiedSignature, authorize?: false)
  end

  test "a credential token for another hash is refused by the provider", %{ctx: ctx} do
    second = ctx |> start() |> then(&approve(ctx, &1)) |> redirected_to()
    other = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
    conn = approve(ctx, second, "Olena Kovalenko", &Map.put(&1, "hashes", other))
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "failed"

    assert [%{status: :failed, failure: failure}] =
             Ash.read!(QualifiedSignature, authorize?: false)

    assert failure =~ "sign_hash"
  end

  test "the emulator's approval page already knows the account in step 2" do
    id = "emu-" <> Base.url_encode64("Olena Kovalenko", padding: false)

    conn =
      Plug.Test.conn(:get, "/oauth2/authorize?scope=credential&credentialID=#{id}")
      |> CscEmulator.call(CscEmulator.init([]))

    assert conn.resp_body =~ ~s(value="Olena Kovalenko")
  end
end
