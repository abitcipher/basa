defmodule Basa.Messaging.TelegramWorker do
  use Oban.Worker, queue: :notifications, max_attempts: 5
  use Gettext, backend: BasaWeb.Gettext

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"message_id" => message_id, "recipient_id" => recipient_id}}) do
    message =
      Ash.get!(Basa.Messaging.Message, message_id,
        load: [:sender, conversation: [:lot]],
        authorize?: false
      )

    recipient = Ash.get!(Basa.Accounts.User, recipient_id, authorize?: false)

    if recipient.telegram_id && Basa.Telegram.enabled?() do
      text =
        Gettext.with_locale(BasaWeb.Gettext, to_string(recipient.locale || :en), fn ->
          gettext("%{name} about “%{lot}”:\n\n%{body}\n\nReply to this message to answer.",
            name: BasaWeb.Layouts.display_name(message.sender),
            lot: message.conversation.lot.title,
            body: message.body
          )
        end)

      case Basa.Telegram.send_message(recipient.telegram_id, text) do
        {:ok, %{message_id: tg_id}} ->
          Basa.Messaging.TelegramDelivery
          |> Ash.Changeset.for_create(:create, %{
            conversation_id: message.conversation_id,
            user_id: recipient.id,
            chat_id: recipient.telegram_id,
            telegram_message_id: tg_id
          })
          |> Ash.create!()

          :ok

        {:ok, _} ->
          :ok

        {:error, reason} ->
          {:error, reason}
      end
    else
      :ok
    end
  end
end
