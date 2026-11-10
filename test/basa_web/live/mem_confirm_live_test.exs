defmodule BasaWeb.MemConfirmLiveTest do
  use BasaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Basa.WitnessFixtures
  import Basa.MemFixtures

  require Ash.Query

  alias Basa.Witness.{MemAttest, MemAttestation}

  setup do
    %{ctx: sealed_contract()}
  end

  defp record(tx, role) do
    MemAttestation
    |> Ash.Query.filter(transaction_id == ^tx.id and role == ^role and status == :pending)
    |> Ash.read_one!(authorize?: false)
  end

  test "each party shows a code; MEM posts; both pages show it confirmed", %{ctx: ctx} do
    path = ~p"/transactions/#{ctx.tx.id}"
    {:ok, olena, _} = live(build_conn() |> sign_in(ctx.lessor), path)
    {:ok, max, _} = live(build_conn() |> sign_in(ctx.lessee), path)

    assert has_element?(olena, "#mem-offeror", "not yet")
    olena |> element("#mem-issue") |> render_click()
    assert has_element?(olena, "#mem-code svg")
    assert render(olena) =~ MemAttest.label(ctx.tx)
    max |> element("#mem-issue") |> render_click()

    o = record(ctx.tx, :offeror)
    a = record(ctx.tx, :acceptor)

    requests = %{
      "offeror" => %{challenge: o.challenge, phone: phone()},
      "acceptor" => %{challenge: a.challenge, phone: phone()}
    }

    {bo, ba} = attest_pair(MemAttest.origin(), ctx.tx.basa_hash, requests)

    assert build_conn()
           |> put_req_header("content-type", "application/cbor")
           |> post(URI.parse(MemAttest.submit_url(o)).path, bo)
           |> response(201)

    refute has_element?(olena, "#mem-code")
    assert has_element?(max, "#mem-offeror", "confirmed")
    refute has_element?(olena, "#mem-issue")

    max |> form("#mem-paste-form", %{"code" => text_form(ba)}) |> render_submit()

    assert has_element?(max, "#mem-confirmed")
    assert has_element?(olena, "#mem-confirmed")
  end

  test "a wrong pasted code is refused", %{ctx: ctx} do
    {:ok, view, _} = live(build_conn() |> sign_in(ctx.lessor), ~p"/transactions/#{ctx.tx.id}")
    view |> element("#mem-issue") |> render_click()
    html = view |> form("#mem-paste-form", %{"code" => "memattsig1:AAAA"}) |> render_submit()
    assert html =~ "was not accepted"
    assert has_element?(view, "#mem-code")
  end
end
