defmodule Basa.Telegram.BotTest do
  use Basa.DataCase, async: false

  import Basa.Fixtures
  alias BasaTma.Emulator

  @user %{id: 900_001, first_name: "Olena", username: "olena", language_code: "en"}

  setup do
    previous_adapter = Application.get_env(:ex_gram, :adapter)
    previous_tg = Application.get_env(:basa, :telegram)

    Application.put_env(:ex_gram, :adapter, Emulator.Adapter)

    Application.put_env(:basa, :telegram,
      bot_token: Emulator.token(),
      bot_username: Emulator.bot_username(),
      updates: :emulator
    )

    Application.put_env(:basa_tma, :emulator, Basa.Telegram.emulator_options())

    start_supervised!(ExGram)
    start_supervised!(Emulator)

    start_supervised!(
      {Basa.Telegram.Bot, [method: :test, token: Emulator.token(), handler_mode: :sync]}
    )

    on_exit(fn ->
      Application.put_env(:ex_gram, :adapter, previous_adapter)
      Application.put_env(:basa, :telegram, previous_tg)
      Application.delete_env(:basa_tma, :emulator)
    end)
  end

  defp bot_texts(chat_id) do
    for %{from: :bot} = e <- Emulator.transcript(chat_id), do: e.text
  end

  defp last_bot(chat_id),
    do: chat_id |> Emulator.transcript() |> Enum.filter(&(&1.from == :bot)) |> List.last()

  defp keyboard_texts(entry),
    do: entry.reply_markup["keyboard"] |> List.flatten() |> Enum.map(& &1["text"])

  test "/start opens the Mini App's start screen and shows the menu, with Verify phone first" do
    Emulator.user_sends(@user, {:text, "/start"})

    [welcome, menu] = Emulator.transcript(@user.id) |> Enum.filter(&(&1.from == :bot))
    assert welcome.text =~ "Welcome to BASA"

    assert [%{"text" => "Open BASA", "web_app" => %{"url" => url}}] =
             List.flatten(welcome.reply_markup["inline_keyboard"])

    assert url =~ "/tg?to=%2Fapp"

    assert menu.reply_markup["is_persistent"]

    assert [[%{"request_contact" => true, "text" => "📱 Verify phone"}] | rows] =
             menu.reply_markup["keyboard"]

    assert Enum.all?(rows, &(length(&1) == 2))

    assert keyboard_texts(menu) -- ["📱 Verify phone"] ==
             ["🔍 Find", "📅 Bookings", "💬 Messages", "🎛 My offers", "➕ Add item", "❓ Help"]
  end

  test "the menu is in the person's language, and its buttons work in any language" do
    olena = %{@user | id: 900_011, language_code: "uk"}
    Emulator.user_sends(olena, {:text, "/start"})
    assert "📅 Бронювання" in keyboard_texts(last_bot(olena.id))

    Emulator.user_sends(@user, {:text, "📅 Бронювання"})
    assert last_bot(@user.id).text =~ "Your bookings"

    Emulator.user_sends(@user, {:text, "💬 Messages"})

    assert [%{"web_app" => %{"url" => url}}] =
             List.flatten(last_bot(@user.id).reply_markup["inline_keyboard"])

    assert url =~ "%2Fmessages"

    Emulator.user_sends(@user, {:text, "🎛 My offers"})
    assert length(List.flatten(last_bot(@user.id).reply_markup["inline_keyboard"])) == 2

    Emulator.user_sends(@user, {:text, "🔍 Find"})
    assert last_bot(@user.id).text =~ "Write a city"

    for command <- ["/messages", "/offers", "/help"] do
      Emulator.user_sends(@user, {:text, command})
      assert last_bot(@user.id).reply_markup["inline_keyboard"]
    end
  end

  defp switch_off(services) do
    {:ok, _} =
      Basa.System.update_settings(Basa.System.settings(), %{services_off: services},
        actor: Basa.Fixtures.user(%{role: :admin})
      )
  end

  test "switched off: the bot stays silent" do
    switch_off([:telegram])
    Emulator.user_sends(@user, {:text, "/start"})
    assert bot_texts(@user.id) == []
    assert {:ok, :skipped} = Basa.Telegram.send_message(@user.id, "hello")
  end

  test "searching by city lists published offers" do
    lessor = user()

    published_lot(lessor, basket(lessor, [item(lessor)]), room(lessor, %{city: "Odesa"}), %{
      title: "Vocal studio"
    })

    Emulator.user_sends(@user, {:text, "/search Odesa"})
    reply = last_bot(@user.id)
    assert reply.text =~ "Here is what I found"

    assert [%{"text" => "Vocal studio" <> _}] =
             List.flatten(reply.reply_markup["inline_keyboard"])

    Emulator.user_sends(@user, {:text, "nothing like this"})
    assert last_bot(@user.id).text =~ "Nothing found"
  end

  test "a photo becomes a draft item of the Telegram user" do
    Emulator.user_sends(@user, {:photo, "fake-jpeg-bytes", "image/jpeg"})

    assert last_bot(@user.id).text =~ "Added to your inventory"
    {:ok, user} = Basa.Accounts.TelegramSignIn.find(@user.id)
    assert [item] = Basa.Catalog.list_my_items!(actor: user)
    assert [_photo] = item.photos
  end

  test "sharing your own contact verifies the phone" do
    Emulator.user_sends(@user, {:contact, "+380501234567"})

    assert last_bot(@user.id).text =~ "verified"
    {:ok, user} = Basa.Accounts.TelegramSignIn.find(@user.id)
    assert user.phone == "+380501234567"
    assert user.phone_verified_at

    refute "📱 Verify phone" in keyboard_texts(last_bot(@user.id))
    Emulator.user_sends(@user, {:text, "/start"})
    refute "📱 Verify phone" in keyboard_texts(last_bot(@user.id))
    assert "❓ Help" in keyboard_texts(last_bot(@user.id))
  end

  test "a reply in Telegram lands in the BASA conversation" do
    {:ok, lessor} =
      Basa.Accounts.TelegramSignIn.sign_in(%{
        telegram_id: @user.id,
        display_name: "Olena",
        locale: :en
      })

    lot = published_lot(lessor, basket(lessor, [item(lessor)]), room(lessor))
    lessee = user()

    {:ok, conv} = Basa.Messaging.start_conversation(lot.id, actor: lessee)
    {:ok, message} = Basa.Messaging.send_message(conv.id, "Is Friday free?", actor: lessee)

    :ok =
      perform_job(Basa.Messaging.TelegramWorker, %{
        message_id: message.id,
        recipient_id: lessor.id
      })

    copy = last_bot(@user.id)
    assert copy.text =~ "Is Friday free?"

    Emulator.user_sends(@user, {:text, "Yes, from 10:00"}, copy.id)
    assert last_bot(@user.id).text == "Sent."

    bodies =
      Basa.Messaging.list_messages!(conv.id, actor: lessee) |> Enum.map(&{&1.body, &1.channel})

    assert {"Yes, from 10:00", :telegram} in bodies
  end

  test "all bot replies are delivered (no rejected payloads)" do
    for text <- ["/start", "/bookings", "/add", "/search studio", "/messages", "/offers", "/help"],
        do: Emulator.user_sends(@user, {:text, text})

    assert length(bot_texts(@user.id)) == 8
  end

  defp perform_job(worker, args) do
    worker.perform(%Oban.Job{args: Map.new(args, fn {k, v} -> {to_string(k), v} end)})
  end
end
