defmodule BasaWeb.AdminRulesLiveTest do
  use BasaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Basa.Fixtures

  test "non-admins are sent away", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/"}}} =
             conn |> sign_in(user()) |> live(~p"/admin/rules")
  end

  test "an admin switches a rule off; Edit opens the rule editor", %{conn: conn} do
    admin = user(%{role: :admin})
    {:ok, view, html} = conn |> sign_in(admin) |> live(~p"/admin/rules")
    assert html =~ "A real title"

    view |> element("button[phx-value-key=lot_title_length][phx-value-enabled]") |> render_click()
    refute Basa.Rules.get_rule_set!("lot_title_length", actor: admin).enabled

    refute has_element?(view, "#rule-form")

    assert {:error, {:live_redirect, %{to: "/admin/rules/lot_title_length"}}} =
             view |> element("#edit-lot_title_length") |> render_click()
  end

  test "the visual editor page saves versions and returns simulations for the editor", %{
    conn: conn
  } do
    admin = user(%{role: :admin})
    Basa.Rules.Library.sync()
    {:ok, view, html} = conn |> sign_in(admin) |> live(~p"/admin/rules/lot_price_positive")
    assert html =~ "rules-editor"

    rule = Basa.Rules.get_rule_set!("lot_price_positive", actor: admin)
    context = Jason.encode!(%{"lot" => %{"priceAmount" => 0}})

    render_hook(view, "simulate", %{"graph" => rule.graph, "context" => context})

    assert_reply(view, %{
      simulate: %{
        result: %{
          "result" => %{"valid" => false, "code" => "lot_price_zero"},
          "trace" => %{},
          "snapshot" => _
        }
      }
    })

    render_hook(view, "simulate", %{"graph" => %{"nodes" => "nope"}, "context" => context})
    assert_reply(view, %{simulate: %{error: %{message: _}}})

    render_hook(view, "save_graph", %{"graph" => rule.graph})
    assert Basa.Rules.get_rule_set!("lot_price_positive", actor: admin).version == 2

    render_hook(view, "save_graph", %{"graph" => %{"nodes" => []}})
    assert Basa.Rules.get_rule_set!("lot_price_positive", actor: admin).version == 2
  end

  test "the editor has Graph, JSON and Test input tabs in one space", %{conn: conn} do
    admin = user(%{role: :admin})
    Basa.Rules.Library.sync()
    {:ok, view, _html} = conn |> sign_in(admin) |> live(~p"/admin/rules/lot_price_positive")

    assert has_element?(view, "#rules-tabs-tab-header-1.active-tab", "Graph")
    assert has_element?(view, "#rules-tabs-tab-header-2", "JSON")
    assert has_element?(view, "#rules-tabs-tab-header-3", "Test input")
    assert has_element?(view, "#rules-tabs-tab-panel-1 #rules-editor-root")
    assert has_element?(view, "#rules-tabs-tab-panel-2 #rules-json-root")
    assert has_element?(view, "#rules-tabs-tab-panel-3 #rules-context")
    assert has_element?(view, "#rules-editor[data-show-1][data-show-2][data-show-3]")
    assert has_element?(view, "#rules-editor[data-context]")
    assert has_element?(view, "#rules-test")

    assert render_hook(view, "json_error", %{"message" => "Parse error on line 3"}) =~
             "Parse error on line 3"
  end
end
