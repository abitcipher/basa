defmodule BasaWeb.ImportLiveTest do
  use BasaWeb.ConnCase, async: false

  use Oban.Testing, repo: Basa.Repo

  import Phoenix.LiveViewTest
  import Basa.Fixtures

  alias Basa.Import

  @text "The user takes full responsibility for how the imported content is used."

  setup do
    Req.Test.set_req_test_to_shared()

    html = File.read!("test/support/fixtures/import/shop_table_cp1251.html")

    Req.Test.stub(Import, fn conn ->
      conn |> Plug.Conn.put_resp_content_type("text/html", nil) |> Plug.Conn.send_resp(200, html)
    end)

    %{admin: user(%{role: :admin}), owner: user()}
  end

  test "the admin grants access by email and publishes the agreement", %{conn: conn} = ctx do
    {:error, {_, %{to: "/"}}} = conn |> sign_in(ctx.owner) |> live(~p"/admin/import")

    {:ok, view, _} = conn |> sign_in(ctx.admin) |> live(~p"/admin/import")
    assert has_element?(view, "#agreement-none")

    view |> form("#grant-form", %{email: "nobody@example.com"}) |> render_submit()
    assert render(view) =~ "No user with this email."

    view |> form("#grant-form", %{email: to_string(ctx.owner.email)}) |> render_submit()
    assert has_element?(view, "[id^=access-]", to_string(ctx.owner.email))

    view |> form("#agreement-form", %{body: @text}) |> render_submit()
    assert Import.current_agreement().version == 1
    refute has_element?(view, "#agreement-none")
  end

  test "the owner confirms the agreement, then creates a source", %{conn: conn} = ctx do
    {:ok, view, _} = conn |> sign_in(ctx.owner) |> live(~p"/my/import")
    assert has_element?(view, "#import-none")

    {:ok, _} = Import.grant_access(ctx.owner.id, actor: ctx.admin)
    {:ok, _} = Import.publish_agreement(@text, actor: ctx.admin)

    {:ok, view, _} = conn |> sign_in(ctx.owner) |> live(~p"/my/import")
    assert has_element?(view, "#import-agreement", @text)

    view |> form("#agreement-confirm") |> render_submit()
    refute Import.allowed?(ctx.owner)

    view |> form("#agreement-confirm", %{read: "true"}) |> render_submit()
    assert Import.allowed?(ctx.owner)

    {:error, {:live_redirect, %{to: "/my/import/" <> id}}} =
      view
      |> form("#source-form",
        source: %{
          name: "Fender shop",
          urls: "http://shop.example/p/101\nhttp://shop.example/p/102"
        }
      )
      |> render_submit()

    {:ok, source} = Import.get_source(id, actor: ctx.owner)
    assert source.sample_urls == ["http://shop.example/p/101", "http://shop.example/p/102"]
  end

  describe "a source" do
    setup ctx do
      {:ok, _} = Import.grant_access(ctx.owner.id, actor: ctx.admin)
      {:ok, a} = Import.publish_agreement(@text, actor: ctx.admin)

      {:ok, _} =
        Import.accept_agreement(Import.access_for(ctx.owner), a.version, actor: ctx.owner)

      {:ok, source} =
        Import.create_source(
          %{name: "Fender shop", sample_urls: ["http://shop.example/p/101"], browser: :never},
          actor: ctx.owner
        )

      %{source: source, amps: category()}
    end

    test "the open tab is in the address, so a reload keeps it", %{conn: conn} = ctx do
      conn = sign_in(conn, ctx.owner)
      {:ok, view, _} = live(conn, ~p"/my/import/#{ctx.source.id}")

      view |> element("#tab-catalogue") |> render_click()
      assert_patch(view, ~p"/my/import/#{ctx.source.id}?tab=catalogue")

      {:ok, view, _} = live(conn, ~p"/my/import/#{ctx.source.id}?tab=catalogue")
      assert view |> element("#tab-catalogue") |> render() =~ "primary"

      {:ok, view, _} = live(conn, ~p"/my/import/#{ctx.source.id}?tab=nope")
      assert view |> element("#tab-found") |> render() =~ "primary"
    end

    test "reads a sample, picks a value on the preview, tests the recipe", %{conn: conn} = ctx do
      {:ok, view, _} = conn |> sign_in(ctx.owner) |> live(~p"/my/import/#{ctx.source.id}")

      view |> element("#read-page") |> render_click()
      render_async(view)
      assert has_element?(view, "#found-brand", "Fender")
      assert has_element?(view, "#found-price", "42900")

      view |> element("#tab-pick") |> render_click()
      preview = view |> element("#page-preview") |> render()
      assert preview =~ ~s(sandbox="allow-same-origin")
      refute preview =~ "&lt;script"

      view |> form("#field-form", %{field: "model"}) |> render_change()

      render_hook(view, "picked", %{
        "chain" => [
          %{"tag" => "html", "nth" => 1},
          %{"tag" => "body", "nth" => 1},
          %{"tag" => "table", "nth" => 2},
          %{"tag" => "tbody", "nth" => 1},
          %{"tag" => "tr", "nth" => 4},
          %{"tag" => "td", "nth" => 2}
        ],
        "text" => "Twin Reverb"
      })

      assert has_element?(view, "#suggestion-0", "Модель")
      view |> element("#suggestion-0 button") |> render_click()
      assert has_element?(view, "#rule-model")

      {:ok, source} = Import.get_source(ctx.source.id, actor: ctx.owner)
      assert source.recipe["fields"]["model"] == %{"from" => "spec", "label" => "Модель"}

      view |> element("#tab-test") |> render_click()
      view |> element("#run-test") |> render_click()
      render_async(view)
      assert has_element?(view, "#test-0", "Fender Twin Reverb")
      assert has_element?(view, "#test-0", "42900 UAH")

      amps = ctx.amps
      view |> form("#categories-form", %{default: amps.id}) |> render_submit()

      Req.Test.stub(Basa.Images, fn conn ->
        Plug.Conn.send_resp(conn, 200, Basa.OpenverseStub.jpeg(conn.request_path))
      end)

      view |> element("#import-all") |> render_click()
      render_async(view, 2_000)
      assert has_element?(view, "#entries", "Added as a draft")

      [entry] = Import.list_entries!(actor: ctx.owner)
      item = Basa.Catalog.get_item!(entry.item_id, actor: ctx.owner)
      assert item.title == "Fender Twin Reverb" and item.model == "Twin Reverb"
      assert item.category_id == amps.id
      assert has_element?(view, ~s(#entry-#{entry.id} a[href="/my/items/#{item.id}"]))

      view |> element("#tab-found") |> render_click()
      assert has_element?(view, "#found-model", "Your pick")
    end

    test "the catalogue: settings, the links a crawl would take, crawling", %{conn: conn} = ctx do
      Req.Test.stub(Import, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("text/html")
        |> Plug.Conn.send_resp(
          200,
          ~s(<a href="/p/1">A</a> <a href="/p/2">B</a> <a href="/about">About</a>)
        )
      end)

      {:ok, view, _} = conn |> sign_in(ctx.owner) |> live(~p"/my/import/#{ctx.source.id}")
      view |> element("#tab-catalogue") |> render_click()

      view
      |> form("#catalogue-form",
        catalogue: %{
          urls: "http://shop.example/catalog/",
          link_pattern: "/p/",
          max_pages: "5",
          max_items: "50",
          refresh: "weekly"
        }
      )
      |> render_submit()

      {:ok, source} = Import.get_source(ctx.source.id, actor: ctx.owner)
      assert source.catalogue_urls == ["http://shop.example/catalog/"]
      assert source.refresh == :weekly and source.max_pages == 5

      view |> element("#find-links") |> render_click()
      render_async(view)
      assert has_element?(view, "#found-links", "2 item pages on 1 catalogue pages.")
      assert has_element?(view, "#found-links li", "http://shop.example/p/2")

      view |> element("#crawl-now") |> render_click()
      assert_enqueued(worker: Basa.Import.CrawlWorker, args: %{source_id: ctx.source.id})
    end

    test "a stranger, or the owner after revoking, is sent back", %{conn: conn} = ctx do
      {:error, {:live_redirect, %{to: "/my/import"}}} =
        conn |> sign_in(user()) |> live(~p"/my/import/#{ctx.source.id}")

      {:ok, _} = Import.revoke_access(Import.access_for(ctx.owner), actor: ctx.admin)

      {:error, {:live_redirect, %{to: "/my/import"}}} =
        conn |> sign_in(ctx.owner) |> live(~p"/my/import/#{ctx.source.id}")
    end
  end
end
