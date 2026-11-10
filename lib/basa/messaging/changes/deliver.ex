defmodule Basa.Messaging.Changes.Deliver do
  use Ash.Resource.Change

  alias Basa.Messaging.Conversation

  @impl true
  def change(changeset, _opts, _context) do
    changeset
    |> Ash.Changeset.after_action(fn _changeset, message ->
      message.conversation_id
      |> then(&Ash.get!(Conversation, &1, authorize?: false))
      |> Ash.Changeset.for_update(:touch, %{sender_id: message.sender_id}, authorize?: false)
      |> Ash.update!(authorize?: false)

      {:ok, message}
    end)
    |> Ash.Changeset.after_transaction(fn
      _changeset, {:ok, message} ->
        conversation = Ash.get!(Conversation, message.conversation_id, authorize?: false)
        other = Conversation.other_party(conversation, message.sender_id)

        Phoenix.PubSub.broadcast(
          Basa.PubSub,
          topic(message.conversation_id),
          {:new_message, message}
        )

        Basa.Events.notify_user(other, {:unread_changed, conversation.id})

        %{message_id: message.id, recipient_id: other}
        |> Basa.Messaging.TelegramWorker.new()
        |> Oban.insert()

        {:ok, message}

      _changeset, error ->
        error
    end)
  end

  def topic(conversation_id), do: "conversation:#{conversation_id}"
end
