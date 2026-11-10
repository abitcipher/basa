defmodule Basa.ImportDraftsTest do
  use Basa.DataCase, async: true

  import Basa.Fixtures

  alias Basa.Import
  alias Basa.OpenverseStub

  @text "The user takes full responsibility for how the imported content is used."
  @url "http://shop.example/p/101"

  setup do
    admin = user(%{role: :admin})
    owner = user()
    {:ok, _} = Import.grant_access(owner.id, actor: admin)
    {:ok, a} = Import.publish_agreement(@text, actor: admin)
    {:ok, _} = Import.accept_agreement(Import.access_for(owner), a.version, actor: owner)

    {:ok, source} =
      Import.create_source(%{name: "Shop", sample_urls: [@url], browser: :never}, actor: owner)

    serve(File.read!("test/support/fixtures/import/shop_table_cp1251.html"))

    Req.Test.stub(Basa.Images, fn conn ->
      Plug.Conn.send_resp(conn, 200, OpenverseStub.jpeg(conn.request_path))
    end)

    %{owner: owner, source: source}
  end

  defp serve(html) do
    Req.Test.stub(Import, fn conn ->
      conn |> Plug.Conn.put_resp_content_type("text/html", nil) |> Plug.Conn.send_resp(200, html)
    end)
  end

  defp item_of(entry, owner), do: Basa.Catalog.get_item!(entry.item_id, actor: owner)

  test "a page becomes a private item with its photos; again, unchanged; changed, updated", ctx do
    {:ok, entry} = Import.import_page(ctx.source, @url, ctx.owner)
    assert entry.status == :created

    item = item_of(entry, ctx.owner)
    assert item.title == "Fender Twin Reverb"
    assert item.brand == "Fender" and item.model == "Twin Reverb"
    assert Decimal.equal?(item.estimated_value, 42_900) and item.currency == :UAH
    assert length(item.photos) == 2
    assert Enum.all?(item.photos, &String.starts_with?(&1, "items/#{ctx.owner.id}/"))
    assert {:ok, <<0xFF, 0xD8, _::binary>>, "image/jpeg"} = Basa.Storage.get(hd(item.photos))

    assert {:error, _} = Basa.Catalog.get_item(item.id, actor: user())

    assert {:ok, %{status: :unchanged, item_id: id}} =
             Import.import_page(ctx.source, @url, ctx.owner)

    assert id == item.id

    serve(
      File.read!("test/support/fixtures/import/shop_table_cp1251.html")
      |> String.replace(<<"42 900">>, "39 900")
    )

    assert {:ok, %{status: :updated}} = Import.import_page(ctx.source, @url, ctx.owner)
    assert Decimal.equal?(item_of(entry, ctx.owner).estimated_value, 39_900)
    assert item_of(entry, ctx.owner).photos == item.photos
  end

  test "the category from the source's map, its attributes from detail rows", ctx do
    amps =
      category(%{
        attr_schema: %{
          "type" => "object",
          "required" => ["watts"],
          "properties" => %{"watts" => %{"title" => "Power", "type" => "integer"}}
        }
      })

    {:ok, source} =
      Import.update_source(ctx.source, %{category_map: %{"Підсилювачі" => amps.id}},
        actor: ctx.owner
      )

    page = """
    <html><head><meta charset="utf-8"><title>Amp</title></head><body><h1>Amp</h1>
    <table><tr><td>Категорія:</td><td>Підсилювачі</td></tr><tr><td>Power:</td><td>85 Вт</td></tr></table>
    </body></html>
    """

    serve(page)
    {:ok, entry} = Import.import_page(source, @url, ctx.owner)
    item = item_of(entry, ctx.owner)
    assert item.category_id == amps.id
    assert item.attrs == %{"watts" => 85}

    serve(
      String.replace(page, "<tr><td>Power:</td><td>85 Вт</td></tr>", "")
      |> String.replace("Amp", "Amp 2")
    )

    {:ok, entry} = Import.import_page(source, "http://shop.example/p/102", ctx.owner)
    assert entry.status == :created
    assert is_nil(item_of(entry, ctx.owner).category_id)
    assert entry.error =~ "category not set"
  end

  test "pages the rules skip, and pages that fail, are recorded", ctx do
    graph = %{
      "nodes" => [
        %{
          "id" => "in",
          "type" => "inputNode",
          "name" => "Request",
          "position" => %{"x" => 0, "y" => 0}
        },
        %{
          "id" => "map",
          "type" => "expressionNode",
          "name" => "Map",
          "position" => %{"x" => 200, "y" => 0},
          "content" => %{
            "expressions" => [
              %{"id" => "e", "key" => "skip", "value" => "specs['Наявність'] == 'є'"}
            ]
          }
        },
        %{
          "id" => "out",
          "type" => "outputNode",
          "name" => "Response",
          "position" => %{"x" => 400, "y" => 0}
        }
      ],
      "edges" => [
        %{"id" => "a", "sourceId" => "in", "targetId" => "map", "type" => "edge"},
        %{"id" => "b", "sourceId" => "map", "targetId" => "out", "type" => "edge"}
      ]
    }

    {:ok, source} =
      Import.update_source(ctx.source, %{recipe: %{"rules" => graph}}, actor: ctx.owner)

    assert {:ok, %{status: :skipped, item_id: nil}} = Import.import_page(source, @url, ctx.owner)

    Req.Test.stub(Import, &Plug.Conn.send_resp(&1, 404, "gone"))

    assert {:ok, %{status: :failed, error: "HTTP 404"}} =
             Import.import_page(ctx.source, "http://shop.example/gone", ctx.owner)
  end

  test "only for users with access", ctx do
    {:ok, _} = Import.revoke_access(Import.access_for(ctx.owner), actor: user(%{role: :admin}))
    assert {:error, %Ash.Error.Forbidden{}} = Import.import_page(ctx.source, @url, ctx.owner)
  end
end
