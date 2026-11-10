defmodule Basa.ImportCrawlTest do
  use Basa.DataCase, async: true
  use Oban.Testing, repo: Basa.Repo

  import Basa.Fixtures

  alias Basa.Import
  alias Basa.Import.{Crawl, CrawlWorker, PageWorker, RefreshWorker}

  @text "The user takes full responsibility for how the imported content is used."

  defp catalogue(n, next) do
    links =
      for i <- (n * 10 + 1)..(n * 10 + 3),
          do: ~s(<a href="/catalog/product/details/.num/#{i}/">Item #{i}</a>)

    """
    <html><body>
    <a href="/">Home</a> <a href="https://other.example/catalog/product/details/9/">Elsewhere</a>
    <a href="#top">Up</a> <a href="javascript:void(0)">Basket</a> <a href="mailto:shop@example.com">Mail</a>
    <a href="/catalog/product/details/.num/#{n * 10 + 1}/#reviews">Reviews</a>
    #{Enum.join(links, "\n")}
    #{if next, do: ~s(<a href="#{next}">Наступна</a>), else: ""}
    </body></html>
    """
  end

  setup do
    admin = user(%{role: :admin})
    owner = user()
    {:ok, _} = Import.grant_access(owner.id, actor: admin)
    {:ok, a} = Import.publish_agreement(@text, actor: admin)
    {:ok, _} = Import.accept_agreement(Import.access_for(owner), a.version, actor: owner)

    {:ok, source} =
      Import.create_source(
        %{name: "Shop", sample_urls: ["http://shop.example/catalog/product/details/.num/1/"]},
        actor: owner
      )

    {:ok, source} =
      Import.update_source(
        source,
        %{
          catalogue_urls: ["http://shop.example/catalog/amps/"],
          link_pattern: "/catalog/product/details/",
          browser: :never
        },
        actor: owner
      )

    Req.Test.stub(Import, fn
      %{request_path: "/catalog/amps/", query_string: ""} = conn ->
        html(conn, catalogue(1, "/catalog/amps/?page=2"))

      %{request_path: "/catalog/amps/", query_string: "page=2"} = conn ->
        html(conn, catalogue(2, nil))

      conn ->
        Plug.Conn.send_resp(conn, 404, "")
    end)

    %{owner: owner, admin: admin, source: source}
  end

  defp html(conn, body),
    do: conn |> Plug.Conn.put_resp_content_type("text/html") |> Plug.Conn.send_resp(200, body)

  describe "finding item pages" do
    test "links on the same site matching the pattern, without fragments" do
      links =
        Crawl.links(catalogue(1, nil), "http://shop.example/catalog/amps/", "product/details")

      assert links == [
               "http://shop.example/catalog/product/details/.num/11/",
               "http://shop.example/catalog/product/details/.num/12/",
               "http://shop.example/catalog/product/details/.num/13/"
             ]

      assert Crawl.links(catalogue(1, nil), "http://shop.example/", "re:num/1[23]/$") |> length() ==
               2

      assert Crawl.valid_pattern?("re:num(") == false
    end

    test "the next page: rel=next, words, or the owner's selector" do
      base = "http://shop.example/c/"

      assert Crawl.next_link(~s(<link rel="next" href="?page=2">), base, nil) ==
               "http://shop.example/c/?page=2"

      assert Crawl.next_link(~s(<a href="/c/3">Next</a>), base, nil) == "http://shop.example/c/3"

      assert Crawl.next_link(~s(<a href="/c/4" aria-label="Next">→</a>), base, nil) ==
               "http://shop.example/c/4"

      assert Crawl.next_link(~s(<a class="more" href="/c/5">ще</a>), base, "a.more") ==
               "http://shop.example/c/5"

      assert Crawl.next_link(~s(<a href="/c/">»</a>), base, nil) == nil
      assert Crawl.next_link(~s(<a href="https://ads.example/x">»</a>), base, nil) == nil
    end

    test "catalogue pages followed to the end, within the limits", ctx do
      assert {:ok, %{urls: urls, pages: 2}} = Crawl.discover(ctx.source)
      assert length(urls) == 6
      assert "http://shop.example/catalog/product/details/.num/23/" in urls

      assert {:ok, %{urls: [_, _, _], pages: 1}} = Crawl.discover(%{ctx.source | max_pages: 1})
      assert {:ok, %{urls: [_, _]}} = Crawl.discover(%{ctx.source | max_items: 2})
    end

    test "list pages (subcategories, item lists) followed breadth first", ctx do
      Req.Test.stub(Import, fn
        %{request_path: "/catalog/"} = conn ->
          html(
            conn,
            ~s(<a href="/catalog/list/1">Amps</a> <a href="/catalog/list/2">Mics</a> <a href="/about">About</a>)
          )

        %{request_path: "/catalog/list/" <> n} = conn ->
          html(
            conn,
            ~s(<a href="/catalog/product/details/#{n}a/">A</a> <a href="/catalog/product/details/#{n}b/">B</a>)
          )

        conn ->
          Plug.Conn.send_resp(conn, 404, "")
      end)

      source = %{
        ctx.source
        | catalogue_urls: ["http://shop.example/catalog/"],
          list_pattern: "/catalog/list/"
      }

      assert {:ok, %{urls: urls, pages: 3}} = Crawl.discover(source)
      assert length(urls) == 4

      assert {:ok, %{urls: [], pages: 1}} = Crawl.discover(%{source | list_pattern: nil})
    end

    test "a sitemap, and a sitemap index", ctx do
      Req.Test.stub(Import, fn
        %{request_path: "/sitemap.xml"} = conn ->
          Plug.Conn.send_resp(conn, 200, """
          <sitemapindex><sitemap><loc>http://shop.example/sitemap-products.xml</loc></sitemap></sitemapindex>
          """)

        %{request_path: "/sitemap-products.xml"} = conn ->
          Plug.Conn.send_resp(conn, 200, """
          <urlset>
            <url><loc>http://shop.example/catalog/product/details/.num/7/</loc></url>
            <url><loc> http://shop.example/news/1/ </loc></url>
          </urlset>
          """)

        conn ->
          Plug.Conn.send_resp(conn, 404, "")
      end)

      source = %{ctx.source | catalogue_urls: [], use_sitemap: true}

      assert {:ok, %{urls: ["http://shop.example/catalog/product/details/.num/7/"]}} =
               Crawl.discover(source)

      assert {:error, :no_catalogue} = Crawl.discover(%{source | use_sitemap: false})
    end
  end

  describe "jobs" do
    test "a crawl queues the pages, spaced, and records what it found", ctx do
      assert :ok = Import.crawl_now(ctx.source, ctx.owner)
      assert {:error, :forbidden} = Import.crawl_now(ctx.source, user())
      assert_enqueued(worker: CrawlWorker, args: %{source_id: ctx.source.id})

      assert :ok = perform_job(CrawlWorker, %{source_id: ctx.source.id})
      jobs = all_enqueued(worker: PageWorker)
      assert length(jobs) == 6
      assert jobs |> Enum.map(& &1.scheduled_at) |> Enum.uniq() |> length() == 6

      {:ok, source} = Import.get_source(ctx.source.id, actor: ctx.owner)
      assert source.last_crawl_found == 6 and source.last_crawl_error == nil
    end

    test "a page job imports for the owner; nothing once access is revoked", ctx do
      Req.Test.stub(Import, fn conn ->
        html(conn, ~s(<html><head><title>Amp</title></head><body><h1>Amp 11</h1></body></html>))
      end)

      url = "http://shop.example/catalog/product/details/.num/11/"
      assert :ok = perform_job(PageWorker, %{source_id: ctx.source.id, url: url})
      assert [%{status: :created, url: ^url}] = Import.list_entries!(actor: ctx.owner)

      {:ok, _} = Import.revoke_access(Import.access_for(ctx.owner), actor: ctx.admin)
      assert :ok = perform_job(PageWorker, %{source_id: ctx.source.id, url: url <> "x"})
      assert :ok = perform_job(CrawlWorker, %{source_id: ctx.source.id})
      refute_enqueued(worker: PageWorker)
    end

    test "the nightly refresh crawls the sources set to refresh", ctx do
      {:ok, _} = Import.update_source(ctx.source, %{refresh: :daily}, actor: ctx.owner)

      {:ok, _} =
        Import.create_source(%{name: "Other", sample_urls: ["http://b.example/1"]},
          actor: ctx.owner
        )

      assert :ok = perform_job(RefreshWorker, %{})
      assert [%{args: %{"source_id" => id}}] = all_enqueued(worker: CrawlWorker)
      assert id == ctx.source.id
    end
  end
end
