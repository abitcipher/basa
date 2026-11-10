defmodule BasaWeb.EncryptedFilesTest do
  use BasaWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Basa.WitnessFixtures

  alias Basa.Witness.{Crypto, Store}

  test "a party opens a sealed file with their device's share, once", %{conn: conn} do
    ctx = sealed_contract(storage_mode: :encrypted, photos: ["the stand, as handed over"])
    tx = ctx.tx
    conn = sign_in(conn, ctx.lessee)
    {:ok, view, _html} = live(conn, ~p"/transactions/#{tx.id}")

    path = ~p"/transactions/#{tx.id}/evidence/0"
    view |> element("#evidence-0 button[phx-value-path='#{path}']") |> render_click()
    assert_push_event(view, "device:unwrap", %{sealed: sealed, aad: aad, for: target})
    assert aad == tx.id

    {:ok, share} =
      Crypto.open_for_device(ctx.box_keys[ctx.lessee.id], Base.decode64!(sealed), aad)

    render_hook(view, "device:share", %{"share" => Base.encode64(share), "for" => target})
    assert_push_event(view, "witness:download", %{url: url})

    assert conn |> get(url) |> response(200) == "the stand, as handed over"
    assert conn |> get(url) |> response(404)
    assert conn |> get(path) |> response(404)

    render_hook(view, "device:share", %{"share" => nil, "for" => target})
    assert render(view) =~ "This device cannot open the files"
    assert Store.sealed_share(tx, :acceptor)
  end

  test "plain mode keeps plain links", %{conn: conn} do
    ctx = sealed_contract()
    {:ok, view, _} = live(sign_in(conn, ctx.lessor), ~p"/transactions/#{ctx.tx.id}")
    assert has_element?(view, "#evidence-1 a[href='/transactions/#{ctx.tx.id}/evidence/1']")
  end
end
