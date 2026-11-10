defmodule BasaWeb.AuthorityRequestsTest do
  use BasaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Basa.Fixtures
  import Basa.WitnessFixtures

  setup do
    %{ctx: sealed_contract(), filer: user(%{role: :admin}), approver: user(%{role: :admin})}
  end

  test "two admins take a request through; the parties then see it", %{
    ctx: ctx,
    filer: filer,
    approver: approver
  } do
    path = ~p"/admin/witness/#{ctx.tx.id}"
    {:ok, view, _} = live(build_conn() |> sign_in(filer), path)

    view
    |> form("#request-form", %{
      "authority" => "Shevchenko District Court",
      "basis" => "court_order",
      "reference" => "761/55/26",
      "received_on" => "2026-10-30"
    })
    |> render_submit()

    assert has_element?(view, "#authority-requests", "761/55/26")
    assert render(view) =~ "Another admin has to decide"
    refute has_element?(view, "button[id^='approve-']")

    {:ok, page, _} = live(build_conn() |> sign_in(ctx.lessee), ~p"/transactions/#{ctx.tx.id}")
    refute has_element?(page, "#authority-access")
    [request] = Ash.read!(Basa.Witness.AuthorityRequest, authorize?: false)

    assert build_conn()
           |> sign_in(filer)
           |> get(~p"/admin/witness/requests/#{request.id}/kit")
           |> response(404)

    {:ok, view2, _} = live(build_conn() |> sign_in(approver), path)
    view2 |> element("#approve-#{request.id}") |> render_click()
    assert render(view2) =~ "Parties told on"

    assert render(page) =~ "Access by an authority"
    assert has_element?(page, "#authority-access", "761/55/26")

    conn = build_conn() |> sign_in(approver) |> get(~p"/admin/witness/requests/#{request.id}/kit")

    assert get_resp_header(conn, "content-disposition") |> hd() =~
             "basa-recovery-kit-761_55_26.json"

    assert render(view2) =~ "recovery kit exported"

    assert json_response(conn, 200)["format"] == "basa-recovery-kit/1"

    assert build_conn()
           |> sign_in(ctx.lessee)
           |> get(~p"/admin/witness/requests/#{request.id}/kit")
           |> response(404)

    view2
    |> form("#opening-#{request.id}", %{
      "key_holders" => "two officers",
      "handed_over_to" => "court registry",
      "report_sha256" => String.duplicate("ab", 32)
    })
    |> render_submit()

    assert render(view2) =~ "Opened by two officers; handed over to court registry."
    assert render(view2) =~ "Authority request"
    assert render(page) =~ "handed over on"
  end

  test "withheld notice needs its legal ground", %{ctx: ctx, filer: filer} do
    {:ok, view, _} = live(build_conn() |> sign_in(filer), ~p"/admin/witness/#{ctx.tx.id}")

    html =
      view
      |> form("#request-form", %{
        "authority" => "Police",
        "basis" => "lawful_request",
        "reference" => "12",
        "withhold" => "true"
      })
      |> render_submit()

    assert html =~ "say why the parties may not be told"
  end
end
