defmodule Basa.Messaging do
  use Ash.Domain, otp_app: :basa

  resources do
    resource Basa.Messaging.Conversation do
      define :start_conversation, action: :start, args: [:lot_id]
      define :list_my_conversations, action: :mine
      define :get_conversation, action: :read, get_by: [:id]
      define :mark_read, action: :mark_read
    end

    resource Basa.Messaging.Message do
      define :send_message, action: :send, args: [:conversation_id, :body]
      define :list_messages, action: :in_conversation, args: [:conversation_id]
    end

    resource Basa.Messaging.TelegramDelivery
  end
end
