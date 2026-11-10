defmodule BasaWeb.MyItemsPhotosTest do
  use BasaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Basa.Fixtures

  @jpeg <<0xFF, 0xD8, 0xFF, 0xE0>> <> :binary.copy(<<0>>, 64)

  defp photos(n, from \\ 1) do
    for i <- from..(from + n - 1),
        do: %{name: "p#{i}.jpg", content: @jpeg, type: "image/jpeg"}
  end

  defp upload(view, files) do
    input = file_input(view, "#item-photos-form", :photos, files)
    for f <- files, do: render_upload(input, f.name)
  end

  test "several photos at once, up to 6 in all, with a size slider", %{conn: conn} do
    lessor = user()
    {:ok, view, _html} = conn |> sign_in(lessor) |> live(~p"/my/items/new")

    assert has_element?(view, "#item-photos-count", "0 of 6 photos")
    refute render(view) =~ ~s(capture="environment")

    upload(view, photos(4))
    assert has_element?(view, "#item-photos-count", "4 of 6 photos")
    assert has_element?(view, "#item-photos [data-thumb-size]")

    upload(view, photos(4, 5))
    assert has_element?(view, "#item-photos-count", "6 of 6 photos")
    assert has_element?(view, "#item-photos-notice", "Up to 6 photos")
    assert has_element?(view, "#item-photos-form.hidden")

    [key | _] =
      view
      |> element("#item-photos-strip")
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("[data-sort-key]")
      |> LazyHTML.attribute("data-sort-key")

    render_click(view, "remove_photo", %{"key" => key})
    assert has_element?(view, "#item-photos-count", "5 of 6 photos")
    refute has_element?(view, "#item-photos-notice")
  end

  test "room photos keep their own limit of 8", %{conn: conn} do
    lessor = user()
    room = room(lessor, %{city_id: geo_city("Odesa").id})
    {:ok, view, _html} = conn |> sign_in(lessor) |> live(~p"/my/rooms/#{room.id}/edit")
    render_click(view, "goto", %{"step" => "2"})

    input = file_input(view, "#room-photos-form", :photos, photos(8))
    for i <- 1..8, do: render_upload(input, "p#{i}.jpg")
    assert has_element?(view, "#room-photos-count", "8 of 8 photos")

    input = file_input(view, "#room-photos-form", :photos, photos(1, 9))
    render_upload(input, "p9.jpg")
    assert has_element?(view, "#room-photos-count", "8 of 8 photos")
    assert has_element?(view, "#room-photos-notice")
  end

  test "the eye icon previews an item as renters see it", %{conn: conn} do
    lessor = user()

    item =
      item(lessor, %{
        title: "Shure SM7B",
        brand: "Shure",
        model: "SM7B",
        description: "With a windscreen",
        estimated_value: 18_000
      })

    {:ok, view, _html} = conn |> sign_in(lessor) |> live(~p"/my/items")
    view |> element("#preview-#{item.id}") |> render_click()
    assert_patch(view, ~p"/my/items/#{item.id}")

    refute has_element?(view, "[role=dialog]")
    refute has_element?(view, "#preview-#{item.id}")
    assert has_element?(view, "#item-preview-body h1", "Shure SM7B")
    html = view |> element("#item-preview-body") |> render()
    assert html =~ "With a windscreen"
    assert html =~ "18000.00 UAH"
    assert html =~ "Market value"

    assert has_element?(view, "#item-preview-edit[href='/my/items/#{item.id}/edit']")
    assert has_element?(view, "#item-preview-body a[href='/my/items']")
  end

  test "nobody previews someone else's item", %{conn: conn} do
    item = item(user())

    assert_raise Ash.Error.Invalid, fn ->
      conn |> sign_in(user()) |> live(~p"/my/items/#{item.id}")
    end
  end
end
