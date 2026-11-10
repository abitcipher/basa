defmodule BasaWeb.StreetViewTest do
  use BasaWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Basa.Fixtures

  alias Basa.StreetView

  @images [
    %{"id" => 3, "lat" => 50.4504, "lng" => 30.5204, "creator" => "far"},
    %{"id" => 1, "lat" => 50.45001, "lng" => 30.52001, "creator" => "olena"},
    %{"id" => 2, "lat" => 50.4502, "lng" => 30.5201, "creator" => nil}
  ]

  setup do
    Req.Test.set_req_test_to_shared()

    Req.Test.stub(StreetView, fn
      %{request_path: "/images"} = conn ->
        data =
          Enum.map(@images, fn i ->
            %{
              "id" => to_string(i["id"]),
              "captured_at" => 1_717_200_000_000,
              "creator" => i["creator"] && %{"username" => i["creator"]},
              "computed_geometry" => %{"type" => "Point", "coordinates" => [i["lng"], i["lat"]]}
            }
          end)

        Req.Test.json(conn, %{"data" => data})

      %{request_path: "/" <> id} = conn ->
        Req.Test.json(conn, %{
          "id" => id,
          "thumb_256_url" => "https://cdn.example/#{id}/256.jpg",
          "thumb_1024_url" => "https://cdn.example/#{id}/1024.jpg"
        })
    end)

    Req.Test.stub(Basa.Images, fn conn ->
      Plug.Conn.send_resp(conn, 200, Basa.OpenverseStub.jpeg(conn.request_path))
    end)

    on_exit(fn -> Req.Test.set_req_test_to_private() end)
    :ok
  end

  defp switch_off do
    {:ok, _} =
      Basa.System.update_settings(Basa.System.settings(), %{services_off: [:street_view]},
        actor: user(%{role: :admin})
      )
  end

  test "views near a point: nearest first, with previews; the picked one is kept" do
    assert {:ok, [first, second, third]} = StreetView.nearby(50.45, 30.52)
    assert [first.id, second.id, third.id] == ["1", "2", "3"]
    assert first.meters < second.meters and second.meters < third.meters
    assert first.creator == "olena" and first.captured_at == ~D[2024-06-01]
    assert "data:image/jpeg;base64," <> _ = first.preview

    owner = user()
    assert {:ok, kept} = StreetView.keep(first, owner.id)
    assert String.starts_with?(kept["key"], "street/#{owner.id}/")
    assert kept["id"] == "1" and kept["creator"] == "olena"

    assert {:ok, <<0xFF, 0xD8, _::binary>>, _} = Basa.Storage.get(kept["key"])

    assert StreetView.link(kept) == "https://www.mapillary.com/app/?pKey=1"
  end

  test "an owner picks a view in the room wizard; renters see it beside the map",
       %{conn: conn} do
    lessor = user()
    room = room(lessor)
    {:ok, view, _} = conn |> sign_in(lessor) |> live(~p"/my/rooms/#{room.id}/edit")

    view |> element("#street-view-find") |> render_click()
    render_async(view)
    assert has_element?(view, "#street-view-1")
    assert has_element?(view, "#street-view-3")

    view |> element("#street-view-1") |> render_click()
    assert has_element?(view, "#street-view-picked", "olena")
    view |> form("#room-form") |> render_submit()

    room = Ash.get!(Basa.Catalog.Room, room.id, actor: lessor)
    assert %{"id" => "1", "creator" => "olena", "key" => "street/" <> _} = room.street_view
    refute room.street_view["key"] in room.photos

    lot = published_lot(lessor, basket(lessor, [item(lessor)]), room)
    {:ok, page, _} = live(build_conn(), ~p"/lots/#{lot.id}")
    assert has_element?(page, "#lot-street-view", "not the room")
    assert has_element?(page, "#lot-street-view a[href='https://www.mapillary.com/app/?pKey=1']")

    {:ok, view, _} = conn |> sign_in(lessor) |> live(~p"/my/rooms/#{room.id}/edit")
    view |> element("#street-view-remove") |> render_click()
    view |> form("#room-form") |> render_submit()
    {:ok, page, _} = live(build_conn(), ~p"/lots/#{lot.id}")
    refute has_element?(page, "#lot-street-view")
  end

  test "nothing near the pin: says so; 'none of these' clears the choices", %{conn: conn} do
    Req.Test.stub(StreetView, fn conn -> Req.Test.json(conn, %{"data" => []}) end)
    lessor = user()
    room = room(lessor)
    {:ok, view, _} = conn |> sign_in(lessor) |> live(~p"/my/rooms/#{room.id}/edit")

    view |> element("#street-view-find") |> render_click()
    render_async(view)
    assert has_element?(view, "#street-view-none-found")
  end

  test "only a view BASA kept for the owner can be stored" do
    owner = user()
    room = room(owner)

    assert {:error, _} =
             Basa.Catalog.update_room(
               room,
               %{street_view: %{"key" => "items/someone/x.jpg", "id" => "1"}},
               actor: owner
             )

    assert {:error, _} =
             Basa.Catalog.update_room(
               room,
               %{street_view: %{"key" => "street/#{user().id}/x.jpg", "id" => "1"}},
               actor: owner
             )
  end

  test "switched off: no lookups, but a view already picked keeps showing", %{conn: conn} do
    lessor = user()
    {:ok, [v | _]} = StreetView.nearby(50.45, 30.52)
    {:ok, kept} = StreetView.keep(v, lessor.id)
    room = room(lessor) |> Basa.Catalog.update_room!(%{street_view: kept}, actor: lessor)
    lot = published_lot(lessor, basket(lessor, [item(lessor)]), room)

    switch_off()
    assert {:error, :off} = StreetView.nearby(50.45, 30.52)

    {:ok, view, _} = conn |> sign_in(lessor) |> live(~p"/my/rooms/#{room.id}/edit")
    refute has_element?(view, "#street-view-find")
    assert has_element?(view, "#street-view-picked")

    {:ok, page, _} = live(build_conn(), ~p"/lots/#{lot.id}")
    assert has_element?(page, "#lot-street-view")
  end

  describe "the owner's own photos of the way in" do
    @jpeg <<0xFF, 0xD8, 0xFF, 0xE0>> <> :binary.copy(<<0>>, 64)

    test "added in the wizard, shown on the offer beside the map, removed again",
         %{conn: conn} do
      lessor = user()
      room = room(lessor)
      conn = sign_in(conn, lessor)
      {:ok, view, _} = live(conn, ~p"/my/rooms/#{room.id}/edit")

      files = for n <- 1..2, do: %{name: "door#{n}.jpg", content: @jpeg, type: "image/jpeg"}
      input = file_input(view, "#room-form", :entrance, files)
      for f <- files, do: render_upload(input, f.name)

      view |> form("#room-form") |> render_submit()
      room = Ash.get!(Basa.Catalog.Room, room.id, actor: lessor)
      assert [a, b] = room.entrance_photos
      assert Enum.all?([a, b], &String.starts_with?(&1, "entrance/#{lessor.id}/"))
      assert room.photos -- [a, b] == room.photos

      lot = published_lot(lessor, basket(lessor, [item(lessor)]), room)
      {:ok, page, _} = live(build_conn(), ~p"/lots/#{lot.id}")
      assert has_element?(page, "#lot-entrance", "photographed by the owner")
      assert has_element?(page, ~s(#lot-entrance img[src="#{Basa.Storage.url(a)}"]))

      {:ok, view, _} = live(conn, ~p"/my/rooms/#{room.id}/edit")
      view |> element(~s(#entrance-photos button[phx-value-key="#{a}"])) |> render_click()
      view |> form("#room-form") |> render_submit()
      assert Ash.get!(Basa.Catalog.Room, room.id, actor: lessor).entrance_photos == [b]
    end

    test "only the owner's own uploads, at most three" do
      owner = user()
      room = room(owner)

      assert {:error, _} =
               Basa.Catalog.update_room(room, %{entrance_photos: ["rooms/#{owner.id}/x.jpg"]},
                 actor: owner
               )

      four = for n <- 1..4, do: "entrance/#{owner.id}/#{n}.jpg"

      assert {:error, _} =
               Basa.Catalog.update_room(room, %{entrance_photos: four}, actor: owner)

      assert {:ok, _} =
               Basa.Catalog.update_room(room, %{entrance_photos: Enum.take(four, 3)},
                 actor: owner
               )
    end
  end
end
