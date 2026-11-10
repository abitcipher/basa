defmodule Basa.Messaging.TelegramDelivery do
  use Ash.Resource,
    otp_app: :basa,
    domain: Basa.Messaging,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "telegram_deliveries"
    repo Basa.Repo

    references do
      reference :conversation, on_delete: :delete
      reference :user, on_delete: :delete
    end
  end

  actions do
    defaults [:read, create: [:conversation_id, :user_id, :chat_id, :telegram_message_id]]

    read :by_telegram_message do
      argument :chat_id, :integer, allow_nil?: false
      argument :telegram_message_id, :integer, allow_nil?: false
      get? true
      filter expr(chat_id == ^arg(:chat_id) and telegram_message_id == ^arg(:telegram_message_id))
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :chat_id, :integer, allow_nil?: false
    attribute :telegram_message_id, :integer, allow_nil?: false
    create_timestamp :inserted_at
  end

  relationships do
    belongs_to :conversation, Basa.Messaging.Conversation, allow_nil?: false
    belongs_to :user, Basa.Accounts.User, allow_nil?: false
  end

  identities do
    identity :unique_chat_message, [:chat_id, :telegram_message_id]
  end
end
