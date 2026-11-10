defmodule Basa.MessagingTest do
  use Basa.DataCase, async: true

  import Basa.Fixtures
  alias Basa.Messaging

  setup do
    lessor = user()
    lessee = user()
    lot = published_lot(lessor, basket(lessor, [item(lessor)]), room(lessor))
    %{lessor: lessor, lessee: lessee, lot: lot}
  end

  test "a lessee starts one conversation per lot, and both sides can write", ctx do
    {:ok, conv} = Messaging.start_conversation(ctx.lot.id, actor: ctx.lessee)
    assert conv.lessor_id == ctx.lessor.id
    assert {:ok, %{id: same}} = Messaging.start_conversation(ctx.lot.id, actor: ctx.lessee)
    assert same == conv.id

    assert {:ok, _} = Messaging.send_message(conv.id, "Is Friday free?", actor: ctx.lessee)
    assert {:ok, _} = Messaging.send_message(conv.id, "Yes, from 10:00.", actor: ctx.lessor)

    bodies = Messaging.list_messages!(conv.id, actor: ctx.lessor) |> Enum.map(& &1.body)
    assert bodies == ["Is Friday free?", "Yes, from 10:00."]
  end

  test "new messages are unread for the other side until opened", ctx do
    {:ok, conv} = Messaging.start_conversation(ctx.lot.id, actor: ctx.lessee)
    Messaging.send_message!(conv.id, "Hello", actor: ctx.lessee)

    conv = Messaging.get_conversation!(conv.id, actor: ctx.lessor)
    assert conv.lessor_unread
    refute conv.lessee_unread

    assert {:ok, %{lessor_unread: false}} = Messaging.mark_read(conv, actor: ctx.lessor)
  end

  test "outsiders can neither read nor write", ctx do
    {:ok, conv} = Messaging.start_conversation(ctx.lot.id, actor: ctx.lessee)
    Messaging.send_message!(conv.id, "Private", actor: ctx.lessee)
    stranger = user()

    assert {:error, _} = Messaging.get_conversation(conv.id, actor: stranger)
    assert Messaging.list_messages!(conv.id, actor: stranger) == []
    assert {:error, error} = Messaging.send_message(conv.id, "Hi", actor: stranger)
    assert Exception.message(error) =~ "is not yours"
  end

  test "lessors can't open a conversation with themselves", ctx do
    assert {:error, error} = Messaging.start_conversation(ctx.lot.id, actor: ctx.lessor)
    assert Exception.message(error) =~ "your own offer"
  end

  test "empty messages are rejected", ctx do
    {:ok, conv} = Messaging.start_conversation(ctx.lot.id, actor: ctx.lessee)
    assert {:error, _} = Messaging.send_message(conv.id, "   ", actor: ctx.lessee)
  end

  test "conversation partners see each other's name but not contact details", ctx do
    {:ok, conv} = Messaging.start_conversation(ctx.lot.id, actor: ctx.lessee)
    conv = Messaging.get_conversation!(conv.id, actor: ctx.lessee, load: [:lessor])

    assert conv.lessor.display_name == ctx.lessor.display_name
    assert %Ash.ForbiddenField{} = conv.lessor.email
  end
end
