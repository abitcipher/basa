defmodule Basa.Telegram.Bot do
  use ExGram.Bot, name: :basa_bot, setup_commands: true
  use Gettext, backend: BasaWeb.Gettext

  require Logger
  alias Basa.Accounts.TelegramSignIn
  alias BasaTma.Markup

  command("start",
    description: "Main menu",
    lang: [
      uk: [description: "Головне меню"],
      de: [description: "Hauptmenü"],
      fr: [description: "Menu principal"],
      es: [description: "Menú principal"],
      it: [description: "Menu principale"],
      pl: [description: "Menu główne"],
      ro: [description: "Meniul principal"],
      tr: [description: "Ana menü"]
    ]
  )

  command("search",
    description: "Find a studio, gear or tools",
    lang: [
      uk: [description: "Знайти студію, обладнання чи інструменти"],
      de: [description: "Studio, Ausrüstung oder Werkzeug finden"],
      fr: [description: "Trouver un studio, du matériel ou des outils"],
      es: [description: "Buscar un estudio, equipo o herramientas"],
      it: [description: "Trova uno studio, attrezzatura o strumenti"],
      pl: [description: "Znajdź studio, sprzęt lub narzędzia"],
      ro: [description: "Găsește un studio, echipament sau unelte"],
      tr: [description: "Stüdyo, ekipman veya alet bul"]
    ]
  )

  command("bookings",
    description: "My bookings",
    lang: [
      uk: [description: "Мої бронювання"],
      de: [description: "Meine Buchungen"],
      fr: [description: "Mes réservations"],
      es: [description: "Mis reservas"],
      it: [description: "Le mie prenotazioni"],
      pl: [description: "Moje rezerwacje"],
      ro: [description: "Rezervările mele"],
      tr: [description: "Rezervasyonlarım"]
    ]
  )

  command("messages",
    description: "Messages",
    lang: [
      uk: [description: "Повідомлення"],
      de: [description: "Nachrichten"],
      fr: [description: "Messages"],
      es: [description: "Mensajes"],
      it: [description: "Messaggi"],
      pl: [description: "Wiadomości"],
      ro: [description: "Mesaje"],
      tr: [description: "Mesajlar"]
    ]
  )

  command("offers",
    description: "My offers and schedule",
    lang: [
      uk: [description: "Мої пропозиції й розклад"],
      de: [description: "Meine Angebote und Zeitplan"],
      fr: [description: "Mes offres et planning"],
      es: [description: "Mis ofertas y agenda"],
      it: [description: "Le mie offerte e agenda"],
      pl: [description: "Moje oferty i grafik"],
      ro: [description: "Ofertele mele și programul"],
      tr: [description: "Tekliflerim ve takvim"]
    ]
  )

  command("add",
    description: "Add an item from a photo",
    lang: [
      uk: [description: "Додати річ із фото"],
      de: [description: "Artikel per Foto hinzufügen"],
      fr: [description: "Ajouter un article par photo"],
      es: [description: "Añadir un artículo con una foto"],
      it: [description: "Aggiungi un articolo da una foto"],
      pl: [description: "Dodaj przedmiot ze zdjęcia"],
      ro: [description: "Adaugă un articol dintr-o fotografie"],
      tr: [description: "Fotoğraftan ürün ekle"]
    ]
  )

  command("help",
    description: "Help",
    lang: [
      uk: [description: "Довідка"],
      de: [description: "Hilfe"],
      fr: [description: "Aide"],
      es: [description: "Ayuda"],
      it: [description: "Aiuto"],
      pl: [description: "Pomoc"],
      ro: [description: "Ajutor"],
      tr: [description: "Yardım"]
    ]
  )

  middleware(ExGram.Middleware.IgnoreUsername)

  @impl ExGram.Handler
  def init(opts) do
    url = app_url("/app")

    if String.starts_with?(url, "https://") do
      button = Markup.menu_button("BASA", url)

      case ExGram.set_chat_menu_button(menu_button: button, bot: opts[:bot]) do
        {:ok, _} -> :ok
        error -> Logger.warning("telegram menu button not set: #{inspect(error)}")
      end
    end

    :ok
  end

  def handle(update, context) do
    if Basa.Telegram.enabled?(), do: dispatch(update, context), else: context
  end

  defp dispatch({:command, :start, msg}, context) do
    with_locale(msg.from, fn ->
      verified? = phone_verified?(msg.from)

      context
      |> answer(
        gettext(
          "Welcome to BASA! Book studios, gear, tools and people's time, or rent out your own.\n\nSend me a photo of something you rent out, and I'll add it to your inventory."
        ),
        reply_markup: open_keyboard([{gettext("Open BASA"), "/app"}])
      )
      |> answer(
        if(verified?,
          do: gettext("The menu is below the message field."),
          else:
            gettext(
              "The menu is below the message field. Tap “Verify phone” to confirm your number."
            )
        ),
        reply_markup: menu_keyboard(verified?)
      )
    end)
  end

  defp dispatch({:command, :messages, msg}, context), do: run_menu(:messages, msg, context)
  defp dispatch({:command, :offers, msg}, context), do: run_menu(:offers, msg, context)
  defp dispatch({:command, :help, msg}, context), do: run_menu(:help, msg, context)

  defp dispatch({:command, :search, %{text: text} = msg}, context), do: search(text, msg, context)

  defp dispatch({:text, text, %{reply_to_message: %{message_id: reply_id}} = msg}, context) do
    with_locale(msg.from, fn ->
      case reply_into_conversation(msg.chat.id, reply_id, msg.from.id, text) do
        :ok -> answer(context, gettext("Sent."))
        :not_ours -> search(text, msg, context)
        :error -> answer(context, gettext("Couldn't send the reply. Please answer in BASA."))
      end
    end)
  end

  defp dispatch({:text, text, msg}, context) do
    case menu_action(text) do
      nil -> search(text, msg, context)
      action -> run_menu(action, msg, context)
    end
  end

  defp dispatch({:command, :bookings, msg}, context) do
    with_locale(msg.from, fn ->
      answer(context, gettext("Your bookings:"),
        reply_markup: open_keyboard([{gettext("Open bookings"), "/bookings"}])
      )
    end)
  end

  defp dispatch({:command, :add, msg}, context) do
    with_locale(msg.from, fn ->
      answer(context, gettext("Send me one or more photos of the item."))
    end)
  end

  defp dispatch({:message, %{photo: [_ | _] = sizes} = msg}, context) do
    with_locale(msg.from, fn ->
      case add_item_from_photo(msg.from, Enum.max_by(sizes, & &1.file_size)) do
        {:ok, item} ->
          answer(
            context,
            gettext(
              "Added to your inventory. I'm looking at the photo; check the details when you're ready."
            ),
            reply_markup:
              open_keyboard([{gettext("Check the item"), "/my/items/#{item.id}/edit"}])
          )

        {:error, reason} ->
          Logger.warning("telegram photo failed: #{inspect(reason)}")
          answer(context, gettext("Sorry, I couldn't save that photo. Please try again."))
      end
    end)
  end

  defp dispatch(
         {:message, %{contact: %{user_id: uid, phone_number: phone}, from: %{id: uid} = from}},
         context
       ) do
    with_locale(from, fn ->
      with {:ok, user} <-
             TelegramSignIn.sign_in(
               Basa.Telegram.user_attrs(Map.from_struct(from) |> stringify())
             ),
           {:ok, _} <-
             user
             |> Ash.Changeset.for_update(
               :verify_phone_via_telegram,
               %{phone: normalize_phone(phone)},
               authorize?: false
             )
             |> Ash.update(authorize?: false) do
        answer(context, gettext("Thanks, your phone number is verified."),
          reply_markup: menu_keyboard(true)
        )
      else
        _ -> answer(context, gettext("Could not verify the number."))
      end
    end)
  end

  defp dispatch({:message, %{contact: _}}, context),
    do: answer(context, gettext("Please share your own contact using the button."))

  defp dispatch(update, context) do
    Logger.debug("bot ignored update: #{inspect(update, limit: 8)}")
    context
  end

  @menu [:find, :bookings, :messages, :offers, :add, :help]

  defp menu_label(:find), do: "🔍 " <> gettext("Find")
  defp menu_label(:bookings), do: "📅 " <> gettext("Bookings")
  defp menu_label(:messages), do: "💬 " <> gettext("Messages")
  defp menu_label(:offers), do: "🎛 " <> gettext("My offers")
  defp menu_label(:add), do: "➕ " <> gettext("Add item")
  defp menu_label(:help), do: "❓ " <> gettext("Help")
  defp menu_label(:verify), do: "📱 " <> gettext("Verify phone")

  def menu_keyboard(verified?) do
    rows = @menu |> Enum.map(&menu_label/1) |> Enum.chunk_every(2)

    rows =
      if verified?,
        do: rows,
        else: [[{menu_label(:verify), :request_contact}] | rows]

    Markup.reply_keyboard(rows)
  end

  def menu_action(text) do
    text = String.trim(text || "")

    Enum.find_value(Basa.I18n.codes(), fn lang ->
      Gettext.with_locale(BasaWeb.Gettext, lang, fn ->
        Enum.find(@menu, &(menu_label(&1) == text))
      end)
    end)
  end

  defp run_menu(:find, msg, context) do
    with_locale(msg.from, fn ->
      answer(
        context,
        gettext("Write a city or what you need, for example “Odesa” or “microphone”."),
        reply_markup: open_keyboard([{gettext("Open search"), "/"}])
      )
    end)
  end

  defp run_menu(:bookings, msg, context), do: dispatch({:command, :bookings, msg}, context)
  defp run_menu(:add, msg, context), do: dispatch({:command, :add, msg}, context)

  defp run_menu(:messages, msg, context) do
    with_locale(msg.from, fn ->
      answer(context, gettext("Your conversations with owners and renters:"),
        reply_markup: open_keyboard([{gettext("Open messages"), "/messages"}])
      )
    end)
  end

  defp run_menu(:offers, msg, context) do
    with_locale(msg.from, fn ->
      answer(context, gettext("Your offers and their bookings:"),
        reply_markup:
          open_keyboard([{gettext("My offers"), "/my"}, {gettext("Schedule"), "/my/schedule"}])
      )
    end)
  end

  defp run_menu(:help, msg, context) do
    with_locale(msg.from, fn ->
      answer(
        context,
        gettext(
          "Use the menu below: find a place or gear, see your bookings and messages, manage your offers, or send a photo to add an item. The full app opens with the BASA button."
        ),
        reply_markup: open_keyboard([{gettext("Open BASA"), "/app"}, {gettext("Help"), "/help"}])
      )
    end)
  end

  defp phone_verified?(from) do
    case TelegramSignIn.find(from.id) do
      {:ok, %{phone_verified_at: %DateTime{}}} -> true
      _ -> false
    end
  end

  defp find_lots(""), do: Basa.Search.find_lots(%{}, actor: nil, limit: 5)

  defp find_lots(text) do
    find = &Basa.Search.find_lots(&1, actor: nil, limit: 5)

    case Basa.Geo.find_by_name(text) do
      %{id: id} ->
        find.(%{city_id: id})

      nil ->
        case find.(%{city: text}) do
          [] -> find.(%{q: text})
          lots -> lots
        end
    end
  end

  defp search(text, msg, context) do
    with_locale(msg.from, fn ->
      text = String.trim(text || "")

      case find_lots(text) do
        [] ->
          answer(
            context,
            gettext("Nothing found. Try a city (for example Odesa or Berlin) or another word.")
          )

        lots ->
          buttons =
            Enum.map(lots, fn lot ->
              {"#{lot.title} · #{Basa.Money.format(lot.price_amount, lot.currency)}",
               "/lots/#{lot.id}"}
            end)

          answer(context, gettext("Here is what I found:"), reply_markup: open_keyboard(buttons))
      end
    end)
  end

  defp reply_into_conversation(chat_id, reply_id, telegram_id, text) do
    with {:ok, delivery} <-
           Basa.Messaging.TelegramDelivery
           |> Ash.Query.for_read(:by_telegram_message, %{
             chat_id: chat_id,
             telegram_message_id: reply_id
           })
           |> Ash.read_one(),
         %{} <- delivery,
         {:ok, %{id: user_id} = user} <- TelegramSignIn.find(telegram_id),
         true <- user_id == delivery.user_id do
      case Basa.Messaging.send_message(delivery.conversation_id, text, %{channel: :telegram},
             actor: user
           ) do
        {:ok, _} -> :ok
        {:error, _} -> :error
      end
    else
      _ -> :not_ours
    end
  end

  defp add_item_from_photo(from, size) do
    with {:ok, user} <-
           TelegramSignIn.sign_in(Basa.Telegram.user_attrs(Map.from_struct(from) |> stringify())),
         {:ok, body, mime} <- Basa.Telegram.download(size.file_id),
         {:ok, key} <- Basa.Storage.store("items/#{user.id}", body, mime),
         {:ok, item} <-
           Basa.Catalog.create_item(%{title: gettext("New item from Telegram"), photos: [key]},
             actor: user
           ) do
      %{item_id: item.id} |> Basa.AI.SuggestWorker.new() |> Oban.insert()
      {:ok, item}
    end
  end

  defp open_keyboard(entries) do
    base = BasaWeb.Endpoint.url()

    Markup.open_buttons(entries, base,
      web_app: String.starts_with?(base, "https://") or Basa.Telegram.emulator?()
    )
  end

  defp app_url(path), do: BasaTma.app_url(BasaWeb.Endpoint.url(), path)

  defp with_locale(from, fun) do
    locale = (from && Basa.I18n.supported(from.language_code)) || "en"
    Gettext.with_locale(BasaWeb.Gettext, locale, fun)
  end

  defp stringify(map), do: Map.new(map, fn {k, v} -> {to_string(k), v} end)

  defp normalize_phone("+" <> _ = phone), do: phone
  defp normalize_phone(phone), do: "+" <> phone
end
