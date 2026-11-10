defmodule Basa.SearchTest do
  use Basa.DataCase, async: false

  import Basa.Fixtures

  @url "http://localhost:7700"
  @key "basa-dev-master-key-change-me"

  setup do
    previous = Application.get_env(:basa, Basa.Search)
    index = "lots_test_#{System.unique_integer([:positive])}"
    Application.put_env(:basa, Basa.Search, url: @url, key: @key, index: index)

    on_exit(fn ->
      Req.delete("#{@url}/indexes/#{index}", auth: {:bearer, @key}, retry: false)
      Application.put_env(:basa, Basa.Search, previous || [])
    end)

    case Req.get("#{@url}/health", retry: false) do
      {:ok, %{status: 200}} -> :ok
      _ -> {:skip, :meilisearch_not_running}
    end
  end

  defp publish(attrs, item_attrs, room_attrs) do
    lessor = user()

    published_lot(
      lessor,
      basket(lessor, [item(lessor, item_attrs)]),
      room(lessor, room_attrs),
      attrs
    )
  end

  @tag :meilisearch
  test "typo-tolerant search, ranked by Meilisearch and filtered by Postgres" do
    studio =
      publish(
        %{title: "Vocal studio Moldavanka"},
        %{title: "Neumann U87", brand: "Neumann", model: "U87"},
        %{city: "Odesa"}
      )

    _drill =
      publish(%{title: "Drill for the weekend"}, %{title: "Bosch GSB 18V", brand: "Bosch"}, %{
        city: "Kyiv",
        lat: 50.45,
        lng: 30.52
      })

    Basa.Search.reindex_all()
    Basa.Search.wait_idle()

    assert [%{id: id}] = Basa.Search.find_lots(%{q: "neuman"})
    assert id == studio.id

    assert [] = Basa.Search.find_lots(%{q: "bosch", city: "Odesa"})
  end

  @tag :meilisearch
  test "archived lots disappear from the index" do
    lot = publish(%{title: "Rehearsal room"}, %{title: "Fender amp"}, %{})
    Basa.Search.index_lot(lot.id)
    Basa.Search.wait_idle()
    assert [_] = Basa.Search.find_lots(%{q: "fender"})

    lot =
      Basa.Catalog.archive_lot!(lot,
        actor: Ash.get!(Basa.Accounts.User, lot.owner_id, authorize?: false)
      )

    Basa.Search.index_lot(lot.id)
    Basa.Search.wait_idle()
    assert Basa.Search.lot_ids("fender") == []
  end

  test "without Meilisearch, search falls back to Postgres" do
    Application.put_env(:basa, Basa.Search, url: nil)
    lot = publish(%{title: "Tool rental"}, %{title: "Makita saw"}, %{})
    assert [%{id: id}] = Basa.Search.find_lots(%{q: "tool"})
    assert id == lot.id
  end

  test "changing a lot queues it for reindexing" do
    lot = publish(%{title: "Studio B"}, %{title: "SM58"}, %{})
    assert_enqueued_lot(lot.id)
  end

  defp assert_enqueued_lot(lot_id) do
    jobs = Basa.Repo.all(Oban.Job) |> Enum.filter(&(&1.worker == "Basa.Search.IndexWorker"))
    assert Enum.any?(jobs, &(&1.args["lot_id"] == lot_id))
  end
end
