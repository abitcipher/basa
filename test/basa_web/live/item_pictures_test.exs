defmodule BasaWeb.ItemPicturesTest do
  use BasaWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Basa.Fixtures
  alias Basa.OpenverseStub

  setup do
    Req.Test.set_req_test_to_shared()
    OpenverseStub.stub()
    :ok
  end

  defp type_title(view, title) do
    view |> form("#item-form", item: %{title: title}) |> render_change()
    render_async(view)
  end

  test "an item without photos gets pictures to pick; the picked one is kept", %{conn: conn} do
    lessor = user()
    {:ok, view, _} = conn |> sign_in(lessor) |> live(~p"/my/items/new")

    assert has_element?(view, "#picture-suggestions", "Type a title")
    assert has_element?(view, "#pictures-info [role=tooltip]", "marked as illustrations")
    type_title(view, "Shure SM7B")
    assert_received {:openverse, %{"q" => "Shure SM7B"}}
    assert has_element?(view, "#picture-2")
    assert has_element?(view, "#picture-grid[phx-hook=BrokenPictures] [data-picture] #picture-0")

    view |> element("#picture-0") |> render_click()
    render_async(view)

    assert has_element?(view, "#item-photos [data-sort-key^='stock/']", "Illustration")
    refute has_element?(view, "#picture-suggestions")

    view |> form("#item-form", item: %{title: "Shure SM7B"}) |> render_submit()
    [item] = Basa.Catalog.list_my_items!(actor: lessor)
    assert [<<"stock/", _::binary>>] = item.photos
    refute item.no_photos
  end

  test "\"No pictures\" is kept with the item", %{conn: conn} do
    lessor = user()
    {:ok, view, _} = conn |> sign_in(lessor) |> live(~p"/my/items/new")
    type_title(view, "Shure SM7B")

    view |> element("#no-pictures") |> render_click()
    assert has_element?(view, "#pictures-off")
    refute has_element?(view, "#picture-suggestions")

    view |> form("#item-form", item: %{title: "Shure SM7B", brand: "Shure"}) |> render_submit()
    [item] = Basa.Catalog.list_my_items!(actor: lessor)
    assert item.no_photos
    assert item.photos == []
    flush()

    {:ok, view, _} = conn |> sign_in(lessor) |> live(~p"/my/items/#{item.id}/edit")
    render_async(view)
    assert has_element?(view, "#pictures-off")
    refute_received {:openverse, _}

    view |> element("#pictures-off button") |> render_click()
    render_async(view)
    assert has_element?(view, "#picture-0")
    view |> form("#item-form") |> render_submit()
    item = Ash.get!(Basa.Catalog.Item, item.id, authorize?: false)
    refute item.no_photos
    assert item.brand == "Shure"
  end

  test "items with photos get no suggestions", %{conn: conn} do
    lessor = user()
    item = item(lessor, %{photos: ["items/x/own.jpg"]})
    {:ok, view, _} = conn |> sign_in(lessor) |> live(~p"/my/items/#{item.id}/edit")
    render_async(view)

    refute has_element?(view, "#picture-suggestions")
    refute_received {:openverse, _}
  end

  test "switched off with nothing kept: the owner just adds photos", %{conn: conn} do
    {:ok, _} =
      Basa.System.update_settings(Basa.System.settings(), %{services_off: [:images]},
        actor: user(%{role: :admin})
      )

    {:ok, view, _} = conn |> sign_in(user()) |> live(~p"/my/items/new")
    type_title(view, "Shure SM7B")

    assert has_element?(view, "#picture-suggestions", "No pictures found")
    refute_received {:openverse, _}

    view |> form("#item-form", item: %{title: "Shure SM7B"}) |> render_submit()
    assert [%{photos: []}] = Basa.Catalog.Item |> Ash.read!(authorize?: false)
  end

  test "renters see kept pictures as illustrations with their credits", %{conn: conn} do
    [picked | _] = Basa.Images.suggest(%{title: "Shure SM7B"})
    {:ok, key} = Basa.Images.attach(picked, %{title: "Shure SM7B"})

    lessor = user()
    mic = item(lessor, %{photos: [key]})
    lot = published_lot(lessor, basket(lessor, [mic]), room(lessor))

    {:ok, view, _} = conn |> live(~p"/lots/#{lot.id}")
    assert has_element?(view, "#photo-credits", "Illustrations, not photos of this item")
    assert has_element?(view, "#photo-credits a[href='#{picked.landing_url}']")
    assert has_element?(view, "#photo-credits", picked.creator)
    assert has_element?(view, "#photo-credits a[href='#{picked.license_url}']", "CC BY 2.0")

    conn = get(build_conn(), "/media/" <> key)
    assert conn.status == 200
    assert <<0xFF, 0xD8, _::binary>> = conn.resp_body
  end

  test "own photos have no credits", %{conn: conn} do
    lessor = user()
    lot = published_lot(lessor, basket(lessor, [item(lessor)]), room(lessor))
    {:ok, view, _} = conn |> live(~p"/lots/#{lot.id}")
    refute has_element?(view, "#photo-credits")
  end

  test "after Openverse says \"too many requests\", BASA waits before asking again" do
    OpenverseStub.stub(self(), search: 429)
    assert {:error, :rate_limited} = Basa.Images.Openverse.search("tripod", 4)
    assert_received {:openverse, _}

    OpenverseStub.stub()
    assert {:error, :rate_limited} = Basa.Images.Openverse.search("tripod", 4)
    refute_received {:openverse, _}
    assert Basa.Images.suggest(%{title: "Tripod"}) == []
  after
    :ets.delete(:basa_images_openverse, :paused_until)
  end

  defp flush do
    receive do
      _ -> flush()
    after
      0 -> :ok
    end
  end
end
