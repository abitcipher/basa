defmodule Basa.ImportBrowserTest do
  use Basa.DataCase, async: false

  @moduletag :browser
  @moduletag timeout: 120_000

  alias Basa.Import
  alias Basa.Import.Browser

  @shell """
  <!doctype html><html><head><meta charset="utf-8"><title>Loading…</title></head>
  <body><div id="root"></div>
  <script id="boot">window.__STATE__ = {"ad": {"location": {"cityName": "Руська", "regionName": "Чернівецька область"}}};</script>
  <script>
    // like many apps: the embedded state is read, then removed
    document.getElementById("boot").remove();
    fetch("/api/item.json").then(r => r.json()).then(d => {
      const ld = document.createElement("script");
      ld.type = "application/ld+json";
      ld.textContent = JSON.stringify({"@type": "Product", name: d.name, image: d.photos,
        offers: {price: d.price, priceCurrency: "UAH"}});
      document.head.appendChild(ld);
      document.getElementById("root").innerHTML = "<h1>" + d.name + "</h1><img src='/a.jpg'>";
    });
  </script></body></html>
  """

  @item %{name: "Будинок у горах", price: 1300, photos: ["/photos/1.jpg", "/photos/2.jpg"]}

  defmodule Site do
    @behaviour Plug
    def init(opts), do: opts

    def call(%{request_path: "/api/item.json"} = conn, _),
      do:
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, Jason.encode!(Basa.ImportBrowserTest.item()))

    def call(%{request_path: "/old"} = conn, _),
      do: conn |> Plug.Conn.put_resp_header("location", "/shell") |> Plug.Conn.send_resp(302, "")

    def call(conn, _),
      do:
        conn
        |> Plug.Conn.put_resp_content_type("text/html")
        |> Plug.Conn.send_resp(200, Basa.ImportBrowserTest.shell())
  end

  def item, do: @item
  def shell, do: @shell

  setup do
    previous = Application.get_env(:basa, Browser)

    Application.put_env(:basa, Browser,
      enabled: true,
      docker_image: "basa/render:0.1",
      docker_args: ["--network", "host"],
      args: ["--allow-private", "--idle-secs", "5"]
    )

    on_exit(fn -> Application.put_env(:basa, Browser, previous) end)

    {:ok, server} = Bandit.start_link(plug: Site, ip: {127, 0, 0, 1}, port: 0, startup_log: false)
    {:ok, {_, port}} = ThousandIsland.listener_info(server)
    %{base: "http://127.0.0.1:#{port}"}
  end

  test "renders a page built by its script, with the JSON it loaded", %{base: base} do
    assert {:ok, page} = Browser.render(base <> "/old")

    assert page.url == base <> "/shell"
    assert page.status == 200
    assert page.html =~ "<h1>Будинок у горах</h1>"
    assert [%{url: url, status: 200, body: body}] = page.json
    assert url == base <> "/api/item.json"
    assert Jason.decode!(body)["price"] == 1300
  end

  test "the import reads it through the browser when the fast path finds a shell", %{base: base} do
    Req.Test.stub(Import, &Plug.Conn.send_resp(&1, 200, @shell))

    assert {:ok, %{via: :browser, fields: f, states: states}} = Import.detect(base <> "/shell")

    assert f.name == "Будинок у горах"
    assert Decimal.equal?(f.price, 1300) and f.currency == "UAH"
    assert f.photos == [base <> "/photos/1.jpg", base <> "/photos/2.jpg"]
    assert f.address == "Руська, Чернівецька область"

    assert %{data: %{"name" => "Будинок у горах"}} =
             Enum.find(states, &(&1.name == base <> "/api/item.json"))
  end

  test "an unreachable page is an error, not a crash" do
    assert {:error, {:browser, _}} = Browser.render("http://127.0.0.1:1/nothing", timeout: 15_000)
    assert {:error, {:browser, _}} = Browser.render("http://127.0.0.1:1/again", timeout: 15_000)
  end
end
