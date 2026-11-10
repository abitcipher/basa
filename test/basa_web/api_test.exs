defmodule BasaWeb.ApiTest do
  use BasaWeb.ConnCase, async: true
  use Oban.Testing, repo: Basa.Repo

  import Basa.Fixtures

  alias Basa.Accounts

  setup do
    owner = user()

    {:ok, key} =
      Accounts.create_api_key("Shop sync", DateTime.add(DateTime.utc_now(), 30, :day),
        actor: owner
      )

    Req.Test.stub(Basa.Images, fn conn ->
      Plug.Conn.send_resp(conn, 200, Basa.OpenverseStub.jpeg(conn.request_path))
    end)

    %{owner: owner, key: key, secret: key.__metadata__.plaintext_api_key}
  end

  defp api(conn, secret \\ nil) do
    conn =
      conn
      |> put_req_header("accept", "application/vnd.api+json")
      |> put_req_header("content-type", "application/vnd.api+json")

    if secret, do: put_req_header(conn, "authorization", "Bearer " <> secret), else: conn
  end

  test "the key is shown once, stored only as a hash, with the basa_ prefix", ctx do
    assert "basa_" <> _ = ctx.secret
    stored = Ash.get!(Accounts.ApiKey, ctx.key.id, actor: ctx.owner)
    refute stored.api_key_hash == ctx.secret
    refute Map.has_key?(stored.__metadata__, :plaintext_api_key)
  end

  test "categories are public", %{conn: conn} do
    category(%{name: %{"en" => "Amplifiers"}})
    conn = conn |> api() |> get("/api/json/categories")
    assert %{"data" => [_ | _]} = json_response(conn, 200)
  end

  test "with a key: create an item with photos by address, list, change, delete",
       %{conn: conn} = ctx do
    amps = category()

    body = %{
      data: %{
        type: "item",
        attributes: %{
          title: "Fender Twin Reverb",
          brand: "Fender",
          estimated_value: "42900",
          currency: "UAH",
          photo_urls: ["https://shop.example/1.jpg", "http://shop.example/2.jpg"]
        },
        relationships: %{}
      }
    }

    body = put_in(body, [:data, :attributes, :category_id], amps.id)

    resp =
      conn
      |> api(ctx.secret)
      |> post("/api/json/items", Jason.encode!(body))
      |> json_response(201)

    %{"data" => %{"id" => id, "attributes" => attrs}} = resp
    assert attrs["title"] == "Fender Twin Reverb"
    assert [_, _] = attrs["photos"]
    assert Enum.all?(attrs["photos"], &String.starts_with?(&1, "items/#{ctx.owner.id}/"))

    item(user(), %{title: "Someone else's"})
    list = build_conn() |> api(ctx.secret) |> get("/api/json/items") |> json_response(200)
    assert [%{"id" => ^id}] = list["data"]

    patch_body = %{data: %{type: "item", id: id, attributes: %{estimated_value: "39900"}}}

    patched =
      build_conn()
      |> api(ctx.secret)
      |> patch("/api/json/items/#{id}", Jason.encode!(patch_body))
      |> json_response(200)

    assert patched["data"]["attributes"]["estimated_value"] in ["39900", "39900.0", 39900]
    assert [_, _] = patched["data"]["attributes"]["photos"]

    assert build_conn() |> api(ctx.secret) |> delete("/api/json/items/#{id}") |> response(200)

    assert build_conn()
           |> api(ctx.secret)
           |> get("/api/json/items")
           |> json_response(200)
           |> Map.get("data") == []
  end

  test "someone else's item can't be changed", %{conn: conn} = ctx do
    other = item(user(), %{title: "Not yours"})
    body = %{data: %{type: "item", id: other.id, attributes: %{title: "Mine now"}}}
    conn = conn |> api(ctx.secret) |> patch("/api/json/items/#{other.id}", Jason.encode!(body))
    assert conn.status in [403, 404]
  end

  test "a wrong, expired or revoked key is refused; no key sees no items", %{conn: conn} = ctx do
    assert conn |> api("basa_nope") |> get("/api/json/items") |> json_response(401)

    :ok = Accounts.revoke_api_key(ctx.key, actor: ctx.owner)
    assert build_conn() |> api(ctx.secret) |> get("/api/json/items") |> json_response(401)

    assert %{"data" => []} = build_conn() |> api() |> get("/api/json/items") |> json_response(200)
  end

  test "keys: at most a year, and a key can't make keys", ctx do
    assert {:error, %Ash.Error.Invalid{}} =
             Accounts.create_api_key("Too long", DateTime.add(DateTime.utc_now(), 400, :day),
               actor: ctx.owner
             )

    with_key = Ash.Resource.put_metadata(ctx.owner, :using_api_key?, true)

    assert {:error, %Ash.Error.Forbidden{}} =
             Accounts.create_api_key("More", DateTime.add(DateTime.utc_now(), 1, :day),
               actor: with_key
             )
  end

  test "the key's last use is noted", %{conn: conn} = ctx do
    conn |> api(ctx.secret) |> get("/api/json/items") |> json_response(200)
    assert %{last_used_at: %DateTime{}} = Ash.get!(Accounts.ApiKey, ctx.key.id, actor: ctx.owner)
  end

  test "over the limit, 429 with retry-after", %{conn: conn} do
    opts = BasaWeb.Plugs.RateLimit.init(limit: 2)
    conn = %{conn | remote_ip: {10, 9, 8, System.unique_integer([:positive]) |> rem(250)}}

    assert BasaWeb.Plugs.RateLimit.call(conn, opts).status == nil
    assert BasaWeb.Plugs.RateLimit.call(conn, opts).status == nil
    limited = BasaWeb.Plugs.RateLimit.call(conn, opts)
    assert limited.status == 429 and limited.halted
    assert [_] = Plug.Conn.get_resp_header(limited, "retry-after")
  end

  defp lot_body(id), do: Jason.encode!(%{data: %{type: "lot", id: id}})

  defp import_on(owner) do
    admin = user(%{role: :admin})
    {:ok, _} = Basa.Import.grant_access(owner.id, actor: admin)

    {:ok, a} =
      Basa.Import.publish_agreement("The user takes full responsibility for imports.",
        actor: admin
      )

    {:ok, _} =
      Basa.Import.accept_agreement(Basa.Import.access_for(owner), a.version, actor: owner)

    :ok
  end

  describe "lots" do
    test "make a draft, change it, submit it for review, archive it", %{conn: conn} = ctx do
      basket = basket(ctx.owner, [item(ctx.owner)])
      room = room(ctx.owner)

      body = %{
        data: %{
          type: "lot",
          attributes: %{
            title: "Vocal studio, hourly",
            basket_id: basket.id,
            room_id: room.id,
            price_amount: "500",
            currency: "UAH",
            price_unit: "hour",
            timezone: "Europe/Kyiv"
          }
        }
      }

      created =
        conn
        |> api(ctx.secret)
        |> post("/api/json/lots", Jason.encode!(body))
        |> json_response(201)

      %{"data" => %{"id" => id, "attributes" => attrs}} = created
      assert attrs["state"] == "draft"

      other = user()
      lot(other, basket(other, [item(other)]), room(other))
      list = build_conn() |> api(ctx.secret) |> get("/api/json/lots") |> json_response(200)
      assert [%{"id" => ^id}] = list["data"]

      change = Jason.encode!(%{data: %{type: "lot", id: id, attributes: %{price_amount: "450"}}})

      changed =
        build_conn()
        |> api(ctx.secret)
        |> patch("/api/json/lots/#{id}", change)
        |> json_response(200)

      assert changed["data"]["attributes"]["price_amount"] in ["450", "450.0", 450]

      submitted =
        build_conn()
        |> api(ctx.secret)
        |> patch("/api/json/lots/#{id}/submit", lot_body(id))
        |> json_response(200)

      assert submitted["data"]["attributes"]["state"] in ["published", "under_review"]

      archived =
        build_conn()
        |> api(ctx.secret)
        |> patch("/api/json/lots/#{id}/archive", lot_body(id))
        |> json_response(200)

      assert archived["data"]["attributes"]["state"] == "archived"
    end

    test "someone else's lot can't be changed or submitted", %{conn: conn} = ctx do
      other = user()
      lot = lot(other, basket(other, [item(other)]), room(other))
      change = Jason.encode!(%{data: %{type: "lot", id: lot.id, attributes: %{title: "Mine"}}})

      resp = conn |> api(ctx.secret) |> patch("/api/json/lots/#{lot.id}", change)
      assert resp.status in [403, 404]

      resp =
        build_conn()
        |> api(ctx.secret)
        |> patch("/api/json/lots/#{lot.id}/submit", lot_body(lot.id))

      assert resp.status in [403, 404]
    end
  end

  describe "import" do
    test "sources: create, list, crawl and import a page (queued), entries",
         %{conn: conn} = ctx do
      :ok = import_on(ctx.owner)

      body = %{
        data: %{
          type: "import_source",
          attributes: %{name: "Fender shop", sample_urls: ["https://shop.example/p/101"]}
        }
      }

      %{"data" => %{"id" => id}} =
        conn
        |> api(ctx.secret)
        |> post("/api/json/import/sources", Jason.encode!(body))
        |> json_response(201)

      settings =
        Jason.encode!(%{
          data: %{
            type: "import_source",
            id: id,
            attributes: %{catalogue_urls: ["https://shop.example/amps"], link_pattern: "/p/"}
          }
        })

      patched =
        build_conn()
        |> api(ctx.secret)
        |> patch("/api/json/import/sources/#{id}", settings)
        |> json_response(200)

      assert patched["data"]["attributes"]["link_pattern"] == "/p/"

      list =
        build_conn() |> api(ctx.secret) |> get("/api/json/import/sources") |> json_response(200)

      assert [%{"id" => ^id}] = list["data"]

      crawl =
        build_conn() |> api(ctx.secret) |> post("/api/json/import/sources/#{id}/crawl", "{}")

      assert %{"queued" => true} = json_response(crawl, 201)
      assert_enqueued(worker: Basa.Import.CrawlWorker, args: %{source_id: id})

      url = "https://shop.example/p/102"
      page = Jason.encode!(%{data: %{url: url}})

      queued =
        build_conn() |> api(ctx.secret) |> post("/api/json/import/sources/#{id}/import", page)

      assert %{"queued" => true, "url" => ^url} = json_response(queued, 201)
      assert_enqueued(worker: Basa.Import.PageWorker, args: %{source_id: id, url: url})

      bad = Jason.encode!(%{data: %{url: "file:///etc/passwd"}})
      resp = build_conn() |> api(ctx.secret) |> post("/api/json/import/sources/#{id}/import", bad)
      assert resp.status == 400

      {:ok, _} =
        Basa.Import.record_entry(%{source_id: id, url: url, status: :created}, actor: ctx.owner)

      entries =
        build_conn()
        |> api(ctx.secret)
        |> get("/api/json/import/entries?filter[source_id]=#{id}")
        |> json_response(200)

      assert [%{"attributes" => %{"url" => ^url, "status" => "created"}}] = entries["data"]
    end

    test "without import access, or someone else's source: refused", %{conn: conn} = ctx do
      :ok = import_on(ctx.owner)
      other = user()

      {:ok, other_key} =
        Accounts.create_api_key("x", DateTime.add(DateTime.utc_now(), 1, :day), actor: other)

      other_secret = other_key.__metadata__.plaintext_api_key

      body =
        Jason.encode!(%{
          data: %{
            type: "import_source",
            attributes: %{name: "x", sample_urls: ["https://a.example/"]}
          }
        })

      resp = conn |> api(other_secret) |> post("/api/json/import/sources", body)
      assert resp.status == 403

      {:ok, source} =
        Basa.Import.create_source(%{name: "Mine", sample_urls: ["https://a.example/"]},
          actor: ctx.owner
        )

      resp =
        build_conn()
        |> api(other_secret)
        |> post("/api/json/import/sources/#{source.id}/crawl", "{}")

      assert resp.status in [403, 404]
      refute_enqueued(worker: Basa.Import.CrawlWorker)

      none =
        build_conn() |> api(other_secret) |> get("/api/json/import/entries") |> json_response(200)

      assert none["data"] == []
    end

    test "while importing is switched off, nothing is queued", %{conn: conn} = ctx do
      :ok = import_on(ctx.owner)

      {:ok, source} =
        Basa.Import.create_source(%{name: "Mine", sample_urls: ["https://a.example/"]},
          actor: ctx.owner
        )

      {:ok, _} =
        Basa.System.update_settings(Basa.System.settings(), %{services_off: [:import]},
          actor: user(%{role: :admin})
        )

      resp = conn |> api(ctx.secret) |> post("/api/json/import/sources/#{source.id}/crawl", "{}")
      assert resp.status == 400
      refute_enqueued(worker: Basa.Import.CrawlWorker)
    end
  end
end
