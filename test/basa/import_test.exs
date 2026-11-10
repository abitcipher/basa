defmodule Basa.ImportTest do
  use Basa.DataCase, async: true

  import Basa.Fixtures

  alias Basa.Import
  alias Basa.Import.{Detect, Page, Price}

  @fixtures "test/support/fixtures/import"

  defp fixture(name), do: File.read!(Path.join(@fixtures, name))

  defp serve(body, content_type \\ "text/html") do
    Req.Test.stub(Import, fn conn ->
      conn |> Plug.Conn.put_resp_content_type(content_type, nil) |> Plug.Conn.send_resp(200, body)
    end)
  end

  describe "detect/2 on pages" do
    test "an old shop page: table rows, gallery links, windows-1251" do
      serve(fixture("shop_table_cp1251.html"), "text/html")

      assert {:ok, %{fields: f, sources: s, specs: specs}} =
               Import.detect("http://shop.example/p/101")

      assert f.name == "Fender Twin Reverb"
      assert f.description == "Ламповий гітарний комбопідсилювач, 85 Вт."
      assert f.brand == "Fender"
      assert f.model == "Twin Reverb"
      assert f.sku == "101"
      assert Decimal.equal?(f.price, 42_900)
      assert f.currency == "UAH"
      assert s.price == :specs

      assert f.photos == [
               "http://shop.example/img/p_101_big.1.jpg",
               "http://shop.example/img/p_101_big.2.jpg"
             ]

      assert f.url == "http://shop.example/p/101"
      assert {"Наявність", "є"} in specs
    end

    test "a classifieds page: JSON-LD plus prerendered state" do
      serve(fixture("ads_state.html"))

      assert {:ok, %{fields: f, sources: s, specs: specs, states: states}} =
               Import.detect("https://ads.example/d/obyavlenie/budinok-ID555.html")

      assert f.name == "Будинок біля озера з банею"
      assert f.description == ~s(Затишний будинок "біля" озера. Баня, мангал.)
      assert Decimal.equal?(f.price, 2500) and f.currency == "UAH"

      assert f.photos == [
               "https://cdn.example/files/a1/image",
               "https://cdn.example/files/a2/image"
             ]

      assert f.category == "budynky"
      assert f.address == "Зікрачі, Київська область"
      assert s.address == :state
      assert f.area == "80 м²" and f.rooms == "3"
      assert {"Кількість спальних місць", "6"} in specs

      assert %{data: %{"ad" => %{"ad" => %{"id" => 555}}}} =
               Enum.find(states, &(&1.name == "__PRERENDERED_STATE__"))

      assert %{data: %{"language" => "uk"}} = Enum.find(states, &(&1.name == "__INIT_CONFIG__"))
    end

    test "microdata, with a nested brand and a lazy image" do
      html = fixture("microdata.html")

      %{fields: f, sources: s, specs: specs} =
        Detect.page(html, "https://mic.example/p/sm7b?ref=1")

      assert f.name == "Shure SM7B" and s.name == :microdata
      assert f.brand == "Shure"
      assert f.model == "SM7B"
      assert f.category == "Microphones"
      assert f.description == "Dynamic vocal microphone."
      assert Decimal.equal?(f.price, Decimal.new("399.00")) and f.currency == "USD"

      assert f.photos == [
               "https://mic.example/media/sm7b-1.webp",
               "https://mic.example/media/sm7b-2.webp"
             ]

      assert f.url == "https://mic.example/p/sm7b"
      assert specs == [{"Weight", "765 g"}, {"Connector", "XLR"}]
    end

    test "one photo in several sizes is kept once, at its largest" do
      urls = [
        "https://s.example/img/amp_small.1.jpg",
        "https://s.example/img/amp-150x150.jpg",
        "https://s.example/img/other.jpg?w=300",
        "https://s.example/img/amp_big.1.jpg",
        "https://s.example/img/amp.jpg",
        "https://s.example/img/other.jpg?w=1200",
        "https://s.example/thumbs/cab.jpg",
        "https://s.example/large/cab.jpg",
        "https://s.example/img/p.jpg?s=1",
        "https://s.example/img/p.jpg?s=2"
      ]

      assert Detect.largest_sizes(urls) == [
               "https://s.example/img/amp_big.1.jpg",
               "https://s.example/img/amp.jpg",
               "https://s.example/img/other.jpg?w=1200",
               "https://s.example/large/cab.jpg",
               "https://s.example/img/p.jpg?s=1",
               "https://s.example/img/p.jpg?s=2"
             ]
    end

    test "a preview inside a gallery link is not a photo of its own" do
      html = ~s(<html><body><h1>Amp</h1>
        <a href="/g/one.jpg"><img src="/p/a1b2.jpg"></a>
        <a href="/g/two.jpg"><img data-src="/p/c3d4.jpg" src="data:image/gif;base64,R0"></a>
        <img itemprop="image" src="/p/a1b2.jpg"></body></html>)

      %{fields: f} = Detect.page(html, "https://s.example/item")
      assert f.photos == ["https://s.example/g/one.jpg", "https://s.example/g/two.jpg"]
    end

    test "a page with nothing structured still gives its heading" do
      %{fields: f, sources: s} =
        Detect.page(
          "<html><head><title>T</title></head><body><h1> Old  amp </h1></body></html>",
          "https://x.example/a"
        )

      assert f.name == "Old amp" and s.name == :html
      refute Map.has_key?(f, :price)
    end

    test "broken JSON-LD and scripts are skipped" do
      html = """
      <script type="application/ld+json">{"@type": "Product", "name": </script>
      <script>window.__X__ = {"a": "}{", "b": [1, {"c": "\\"]"}]}; window.__Y__ = notjson;</script>
      """

      %{json_ld: [], states: states} = Detect.page(html, "https://x.example/")
      assert [%{name: "__X__", data: %{"a" => "}{", "b" => [1, %{"c" => "\"]"}]}}] = states
    end
  end

  test "a detail row with a longer category label (\"Тип товару\") gives the category" do
    html = ~s(<table><tr><td>Тип товару:</td><td>гітарні головні підсилювачі</td></tr></table>)
    %{fields: f, sources: s} = Detect.page(html, "http://shop.example/p")
    assert f.category == "гітарні головні підсилювачі" and s.category == :specs
  end

  describe "prices" do
    test "as pages write them" do
      for {text, amount} <- [
            {"25 380 грн.", "25380"},
            {"1.299,00 €", "1299.00"},
            {"$1,299.99", "1299.99"},
            {"1,299", "1299"},
            {"12,5 zł", "12.5"},
            {"від 850 ₴/доба", "850"},
            {"1.299.000 lei", "1299000"},
            {"1 000 000", "1000000"}
          ] do
        assert Decimal.equal?(Price.amount(text), Decimal.new(amount)), text
      end

      assert Price.amount("Ціна за запитом") == nil
      assert Price.currency("25 380 грн.") == "UAH"
      assert Price.currency("399 USD") == "USD"
      assert Price.currency("12,5 zł") == "PLN"
      assert Price.currency("title") == nil
    end
  end

  describe "fetching" do
    test "follows redirects and refuses other schemes" do
      Req.Test.stub(Import, fn
        %{request_path: "/old"} = conn ->
          conn |> Plug.Conn.put_resp_header("location", "/new") |> Plug.Conn.send_resp(301, "")

        conn ->
          Plug.Conn.send_resp(conn, 200, "<h1>New</h1>")
      end)

      assert {:ok, %{url: "https://shop.example/new", body: "<h1>New</h1>"}} =
               Page.get("https://shop.example/old")

      assert {:error, :bad_url} = Page.get("ftp://shop.example/x")
      assert {:error, :bad_url} = Page.get("file:///etc/passwd")
    end

    test "a page over 5 MB is refused" do
      serve(String.duplicate("a", 5_100_000))
      assert {:error, :too_large} = Page.get("https://shop.example/huge")
    end

    test "errors from the site are reported" do
      Req.Test.stub(Import, &Plug.Conn.send_resp(&1, 403, "no"))
      assert {:error, {:http, 403}} = Import.detect("https://shop.example/p")
    end
  end

  test "without the browser, pages stay on the fast path" do
    serve("<html><head><title>Loading…</title></head><body><div id=root></div></body></html>")

    assert {:ok, %{via: :fast, fields: %{name: "Loading…"}}} =
             Import.detect("https://spa.example/")

    assert {:error, :browser_unavailable} = Import.detect("https://spa.example/", browser: true)
  end

  test "bot checks are recognised, ordinary captchas on forms are not" do
    challenge =
      ~s(<script src="/cdn-cgi/challenge-platform/h/b/orchestrate/chl_page/v1"></script>)

    assert Import.bot_check?(403, challenge)
    assert Import.bot_check?(200, challenge)
    assert Import.bot_check?(403, ~s(<iframe src="https://geo.captcha-delivery.com/captcha/">))

    contact_form = ~s(<form><div class="g-recaptcha"></div></form><h1>Shop</h1>)
    refute Import.bot_check?(200, contact_form)
    assert Import.bot_check?(429, contact_form)
  end

  test "switched off, nothing is fetched" do
    {:ok, _} =
      Basa.System.update_settings(Basa.System.settings(), %{services_off: [:import]},
        actor: user(%{role: :admin})
      )

    Req.Test.stub(Import, fn _ -> flunk("fetched while switched off") end)
    assert {:error, :switched_off} = Import.detect("https://shop.example/p")
  end
end
