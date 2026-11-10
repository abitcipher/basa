defmodule BasaWeb.VerifyLiveTest do
  use BasaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Basa.Fixtures
  import Basa.WitnessFixtures
  require Ash.Query

  setup %{conn: conn} do
    ctx = sealed_contract()
    Map.put(ctx, :conn, conn)
  end

  test "a party downloads a file with its proof; others cannot; it is logged", ctx do
    path = ~p"/transactions/#{ctx.tx.id}/disclose/0"
    conn = ctx.conn |> sign_in(ctx.lessee) |> get(path)
    assert get_resp_header(conn, "content-disposition") |> hd() =~ "attachment"
    package = json_response(conn, 200)
    assert package["format"] == "basa-disclosure/1"

    assert Phoenix.ConnTest.build_conn() |> sign_in(user()) |> get(path) |> response(404)
    assert Phoenix.ConnTest.build_conn() |> get(path) |> response(404)

    assert [%{reason: "disclosure of file 1"}] =
             Basa.Witness.AccessLog
             |> Ash.Query.filter(transaction_id == ^ctx.tx.id and action == :open)
             |> Ash.read!(authorize?: false)
  end

  test "anyone checks a package on /verify, without signing in", ctx do
    {:ok, package} = Basa.Witness.Disclosure.build(ctx.tx, [0])
    {:ok, view, html} = live(Phoenix.ConnTest.build_conn(), ~p"/verify")
    assert html =~ "Check a document"

    upload =
      file_input(view, "#verify-form", :package, [
        %{name: "basa.json", content: Jason.encode!(package), type: "application/json"}
      ])

    render_upload(upload, "basa.json")
    assert has_element?(view, "#verify-result", "Authentic")

    [f] = package["files"]
    tampered = %{package | "files" => [%{f | "content" => Base.encode64("other")}]}

    upload =
      file_input(view, "#verify-form", :package, [
        %{name: "changed.json", content: Jason.encode!(tampered), type: "application/json"}
      ])

    render_upload(upload, "changed.json")
    assert has_element?(view, "#verify-result", "the file was changed")
  end
end
