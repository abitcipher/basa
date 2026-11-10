defmodule BasaWeb.MessagesLiveTest do
  use BasaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Basa.Fixtures

  setup do
    lessor = user(%{display_name: "Olena"})
    lessee = user(%{display_name: "Max"})
    lot = published_lot(lessor, basket(lessor, [item(lessor)]), room(lessor))
    %{lessor: lessor, lessee: lessee, lot: lot}
  end

  test "a lessee messages the lessor from the offer, and the lessor sees it live", ctx do
    lessee_conn = sign_in(build_conn(), ctx.lessee)
    {:ok, lot_view, _} = live(lessee_conn, ~p"/lots/#{ctx.lot.id}")

    {:error, {:live_redirect, %{to: "/messages/" <> conv_id}}} =
      lot_view |> element("button", "Message the lessor") |> render_click()

    lessor_conn = sign_in(build_conn(), ctx.lessor)
    {:ok, lessor_view, _} = live(lessor_conn, ~p"/messages/#{conv_id}")

    {:ok, lessee_view, _} = live(lessee_conn, ~p"/messages/#{conv_id}")
    lessee_view |> form("#message-form", body: "Is Friday free?") |> render_submit()

    assert render(lessor_view) =~ "Is Friday free?"
    assert render(lessee_view) =~ "Is Friday free?"
  end

  test "the unread counter shows on other pages and clears when opened", ctx do
    {:ok, conv} = Basa.Messaging.start_conversation(ctx.lot.id, actor: ctx.lessee)
    Basa.Messaging.send_message!(conv.id, "Hello", actor: ctx.lessee)

    conn = sign_in(build_conn(), ctx.lessor)
    {:ok, view, _} = live(conn, ~p"/messages")
    assert has_element?(view, "a[href='/messages/#{conv.id}']", "new")

    {:ok, _view, _} = live(conn, ~p"/messages/#{conv.id}")
    refute Basa.Messaging.get_conversation!(conv.id, actor: ctx.lessor).lessor_unread
  end

  test "strangers can't open someone else's conversation", ctx do
    {:ok, conv} = Basa.Messaging.start_conversation(ctx.lot.id, actor: ctx.lessee)
    conn = sign_in(build_conn(), user())

    assert {:error, {:live_redirect, %{to: "/messages"}}} = live(conn, ~p"/messages/#{conv.id}")
  end
end
