defmodule Basa.ImagesTest do
  use Basa.DataCase, async: true
  use Oban.Testing, repo: Basa.Repo

  import Basa.Fixtures
  alias Basa.Images
  alias Basa.Images.{Fetch, StockImage}
  alias Basa.OpenverseStub

  defp listing(attrs \\ %{}),
    do: Map.merge(%{title: "Shure SM7B", brand: "Shure", model: "SM7B"}, attrs)

  defp switch_off(services) do
    {:ok, _} =
      Basa.System.update_settings(Basa.System.settings(), %{services_off: services},
        actor: user(%{role: :admin})
      )
  end

  setup do
    OpenverseStub.stub()
    :ok
  end

  describe "suggest/2" do
    test "asks Openverse for openly licensed pictures from brand and model" do
      [first | _] = pictures = Images.suggest(listing())

      assert length(pictures) == 3
      assert_received {:openverse, params}
      assert params["q"] == "Shure SM7B"
      assert params["license"] == "cc0,pdm,by,by-sa"
      assert params["mature"] == "false"

      assert first.source == :openverse
      assert first.key == nil
      assert first.license == "by"
      assert first.creator
      assert String.starts_with?(first.thumbnail, "https://")
    end

    test "a Cyrillic title is looked up by the category's English name" do
      cat = category(%{name: %{"en" => "Microphones", "uk" => "Мікрофони"}})

      Images.suggest(%{title: "Мікрофон для подкастів", category: cat})

      assert_received {:openverse, %{"q" => "Microphones"}}
      refute_received {:openverse, _}
    end

    test "an exact model with no pictures: wider asks, at most three" do
      OpenverseStub.stub(self(), search: %{"results" => []})
      cat = category(%{name: %{"en" => "Microphones"}})

      assert Images.suggest(%{title: "Shure SM7B", brand: "Shure", category: cat}) == []
      assert_received {:openverse, %{"q" => "Shure"}}
      assert_received {:openverse, %{"q" => "Shure SM7B"}}
      assert_received {:openverse, %{"q" => "Shure Microphones"}}
      refute_received {:openverse, _}

      Images.suggest(%{title: "Shure SM7B mic"})
      assert_received {:openverse, %{"q" => "Shure SM7B mic"}}
      assert_received {:openverse, %{"q" => "Shure SM7B"}}
      assert_received {:openverse, %{"q" => "Shure"}}
      refute_received {:openverse, _}
    end

    test "nothing to look for: nothing asked" do
      assert Images.suggest(%{title: "", description: nil}) == []
      refute_received {:openverse, _}
    end

    test "licences that don't allow reuse are left out" do
      body = OpenverseStub.recorded()
      [r | rest] = body["results"]

      OpenverseStub.stub(self(),
        search: %{body | "results" => [%{r | "license" => "by-nc"} | rest]}
      )

      pictures = Images.suggest(listing())
      assert length(pictures) == 2
      refute Enum.any?(pictures, &(&1.license == "by-nc"))
    end
  end

  describe "attach/2" do
    test "keeps the picked picture once, with its credit, and suggests it again" do
      [picked | _] = Images.suggest(listing())

      assert {:ok, "stock/" <> _ = key} = Images.attach(picked, listing())
      assert_received {:download, url}
      assert url == picked.url

      assert {:ok, <<0xFF, 0xD8, _::binary>>, "image/jpeg"} = Basa.Storage.get(key)

      image = Ash.get!(StockImage, %{key: key}, authorize?: false)
      assert image.license == "by"
      assert image.creator == picked.creator
      assert image.landing_url == picked.landing_url
      assert image.queries == ["Shure SM7B"]
      assert image.uses == 1
      assert_enqueued(worker: Basa.Images.IndexWorker, args: %{image_id: image.id})

      assert {:ok, ^key} = Images.attach(picked, listing(%{title: "SM7B mic"}))
      refute_received {:download, _}

      [kept | others] = Images.suggest(listing())
      assert kept.key == key
      assert kept.ref == "stock:" <> image.id
      refute Enum.any?(others, &(&1.source_id == picked.source_id))

      assert {:ok, ^key} = Images.attach(kept, listing())
      image = Ash.get!(StockImage, image.id, authorize?: false)
      assert image.uses == 3
      assert image.queries == ["Shure SM7B", "Shure SM7B SM7B mic"]
    end

    test "the same picture under another id is stored once" do
      OpenverseStub.stub(self(), same_bytes: OpenverseStub.jpeg("same"))
      [a, b | _] = Images.suggest(listing())

      assert {:ok, key} = Images.attach(a, listing())
      assert {:ok, ^key} = Images.attach(b, listing())
      assert [%{uses: 2}] = Ash.read!(StockImage, authorize?: false)
    end

    test "a download that isn't a picture is refused" do
      OpenverseStub.stub(self(), download: &Plug.Conn.send_resp(&1, 200, "<html>nope</html>"))
      [picked | _] = Images.suggest(listing())

      assert {:error, :not_an_image} = Images.attach(picked, listing())
      assert Ash.read!(StockImage, authorize?: false) == []
    end

    test "credits/1 finds the kept pictures among photo keys" do
      [picked | _] = Images.suggest(listing())
      {:ok, key} = Images.attach(picked, listing())

      assert %{^key => %StockImage{}} = Images.credits(["items/x/own.jpg", key])
      assert Images.credits(["items/x/own.jpg"]) == %{}
      assert Images.stock?(key)
      refute Images.stock?("items/x/own.jpg")
    end
  end

  test "switched off: only pictures BASA keeps are suggested, Openverse isn't asked" do
    [picked | _] = Images.suggest(listing())
    {:ok, key} = Images.attach(picked, listing())
    flush()

    switch_off([:images])
    refute Images.enabled?()

    assert [%{key: ^key}] = Images.suggest(listing())
    assert Images.suggest(%{title: "Neumann U87"}) == []
    refute_received {:openverse, _}
  end

  describe "Fetch" do
    test "https only" do
      assert {:error, :not_https} = Fetch.image("http://example.com/a.jpg")
      assert {:error, :not_https} = Fetch.image("file:///etc/passwd")
    end

    test "private and local addresses" do
      for ip <- [
            {127, 0, 0, 1},
            {10, 1, 2, 3},
            {172, 16, 0, 1},
            {192, 168, 1, 1},
            {169, 254, 169, 254},
            {100, 64, 0, 1},
            {0, 0, 0, 0},
            {0, 0, 0, 0, 0, 0, 0, 1},
            {0xFD00, 0, 0, 0, 0, 0, 0, 1},
            {0xFE80, 0, 0, 0, 0, 0, 0, 1},
            {0, 0, 0, 0, 0, 0xFFFF, 0x7F00, 1}
          ],
          do: assert(Fetch.private_ip?(ip), inspect(ip))

      for ip <- [{93, 184, 216, 34}, {8, 8, 8, 8}, {0x2606, 0x4700, 0, 0, 0, 0, 0, 1}],
          do: refute(Fetch.private_ip?(ip), inspect(ip))
    end

    test "redirects are followed only to https" do
      OpenverseStub.stub(self(),
        download: fn conn ->
          case conn.request_path do
            "/start.jpg" ->
              conn
              |> Plug.Conn.put_resp_header("location", "http://pics.example/next.jpg")
              |> Plug.Conn.send_resp(302, "")
          end
        end
      )

      assert {:error, :not_https} = Fetch.image("https://pics.example/start.jpg")
    end

    test "at most 10 MB" do
      OpenverseStub.stub(self(),
        download: &Plug.Conn.send_resp(&1, 200, OpenverseStub.jpeg(:binary.copy("x", 10_000_001)))
      )

      assert {:error, :too_large} = Fetch.image("https://pics.example/huge.jpg")
    end
  end

  defp flush do
    receive do
      _ -> flush()
    after
      0 -> :ok
    end
  end
end
