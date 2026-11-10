defmodule BasaWeb.PhotosLiveTest do
  use BasaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Basa.Fixtures

  setup do
    lessor = user()
    mic = item(lessor, %{title: "Shure SM7B", photos: ["items/a.jpg", "items/b.jpg"]})
    studio = room(lessor, %{title: "Studio A", photos: ["rooms/c.jpg"]})
    %{lessor: lessor, mic: mic, studio: studio}
  end

  test "photo order: a step left or right, or a whole new order of the same photos" do
    alias BasaWeb.PhotoOrder
    assert PhotoOrder.move(~w(a b c), "c", "left") == ~w(a c b)
    assert PhotoOrder.move(~w(a b c), "a", "left") == ~w(a b c)
    assert PhotoOrder.move(~w(a b c), "a", "right") == ~w(b a c)
    assert PhotoOrder.reorder(~w(a b c), ~w(c a b)) == ~w(c a b)
    assert PhotoOrder.reorder(~w(a b c), ~w(c a x)) == ~w(a b c)
  end

  test "widgets off: thumbnails per item and room; delete removes one", ctx do
    {:ok, view, html} = ctx.conn |> sign_in(ctx.lessor) |> live(~p"/my/photos")
    assert html =~ "Shure SM7B" and html =~ "Studio A"

    view |> element("button[phx-value-key='items/a.jpg']") |> render_click()
    assert Ash.reload!(ctx.mic, authorize?: false).photos == ["items/b.jpg"]
  end

  test "widgets on: the library's delete packets, owners only", ctx do
    {:ok, _} =
      Basa.System.update_settings(Basa.System.settings(), %{widgets_enabled: true},
        actor: user(%{role: :admin})
      )

    deleted = fn view, photos ->
      render_hook(view, "widget:event", %{
        "widget" => "photo-library",
        "component" => "PhotoLibrary",
        "type" => "photos.deleted",
        "data" => %{"photos" => photos}
      })
    end

    {:ok, other, _} = ctx.conn |> sign_in(user()) |> live(~p"/my/photos")
    deleted.(other, [%{"owner" => "room", "id" => ctx.studio.id, "key" => "rooms/c.jpg"}])
    assert Ash.reload!(ctx.studio, authorize?: false).photos == ["rooms/c.jpg"]

    {:ok, view, _} = ctx.conn |> sign_in(ctx.lessor) |> live(~p"/my/photos")
    assert has_element?(view, "#photo-library[data-component=PhotoLibrary]")

    deleted.(view, [
      %{"owner" => "item", "id" => ctx.mic.id, "key" => "items/a.jpg"},
      %{"owner" => "item", "id" => ctx.mic.id, "key" => "items/b.jpg"},
      %{"owner" => "room", "id" => ctx.studio.id, "key" => "rooms/c.jpg"}
    ])

    assert Ash.reload!(ctx.mic, authorize?: false).photos == []
    assert Ash.reload!(ctx.studio, authorize?: false).photos == []
    assert_push_event(view, "widget:photo-library", %{type: "photos.changed"})
  end

  test "item form: photos move with the arrows and a dragged order", %{
    conn: conn,
    lessor: lessor,
    mic: mic
  } do
    {:ok, view, _} = conn |> sign_in(lessor) |> live(~p"/my/items/#{mic.id}/edit")
    view |> element("button[phx-click=move_photo][phx-value-key='items/b.jpg']") |> render_click()
    assert view |> element("#item-photos") |> render() =~ ~r/items\/b\.jpg.*items\/a\.jpg/s

    render_hook(view, "reorder_photos", %{"keys" => ["items/a.jpg", "items/b.jpg"]})
    assert view |> element("#item-photos") |> render() =~ ~r/items\/a\.jpg.*items\/b\.jpg/s
  end
end
