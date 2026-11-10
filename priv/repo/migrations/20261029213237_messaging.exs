defmodule Basa.Repo.Migrations.Messaging do
  use Ecto.Migration

  def up do
    create table(:conversations, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :last_message_at, :utc_datetime_usec
      add :lessor_unread, :boolean, null: false, default: false
      add :lessee_unread, :boolean, null: false, default: false

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :updated_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :lot_id,
          references(:lots,
            column: :id,
            name: "conversations_lot_id_fkey",
            type: :uuid,
            prefix: "public",
            on_delete: :delete_all
          ),
          null: false

      add :lessor_id,
          references(:users,
            column: :id,
            name: "conversations_lessor_id_fkey",
            type: :uuid,
            prefix: "public",
            on_delete: :delete_all
          ),
          null: false

      add :lessee_id,
          references(:users,
            column: :id,
            name: "conversations_lessee_id_fkey",
            type: :uuid,
            prefix: "public",
            on_delete: :delete_all
          ),
          null: false
    end

    create unique_index(:conversations, [:lot_id, :lessee_id],
             name: "conversations_unique_lot_lessee_index"
           )

    create table(:messages, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :body, :text, null: false
      add :channel, :text, null: false, default: "web"

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :conversation_id,
          references(:conversations,
            column: :id,
            name: "messages_conversation_id_fkey",
            type: :uuid,
            prefix: "public",
            on_delete: :delete_all
          ),
          null: false

      add :sender_id,
          references(:users,
            column: :id,
            name: "messages_sender_id_fkey",
            type: :uuid,
            prefix: "public",
            on_delete: :delete_all
          ),
          null: false
    end

    create index(:messages, [:conversation_id, :inserted_at])

    create table(:telegram_deliveries, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :chat_id, :bigint, null: false
      add :telegram_message_id, :bigint, null: false

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :conversation_id,
          references(:conversations,
            column: :id,
            name: "telegram_deliveries_conversation_id_fkey",
            type: :uuid,
            prefix: "public",
            on_delete: :delete_all
          ),
          null: false
    end

    create unique_index(:telegram_deliveries, [:chat_id, :telegram_message_id],
             name: "telegram_deliveries_unique_chat_message_index"
           )

    alter table(:telegram_deliveries) do
      add :user_id,
          references(:users,
            column: :id,
            name: "telegram_deliveries_user_id_fkey",
            type: :uuid,
            prefix: "public",
            on_delete: :delete_all
          ),
          null: false
    end
  end

  def down do
    drop constraint(:telegram_deliveries, "telegram_deliveries_user_id_fkey")

    drop constraint(:telegram_deliveries, "telegram_deliveries_conversation_id_fkey")

    alter table(:telegram_deliveries) do
      remove :user_id
    end

    drop_if_exists unique_index(:telegram_deliveries, [:chat_id, :telegram_message_id],
                     name: "telegram_deliveries_unique_chat_message_index"
                   )

    drop table(:telegram_deliveries)

    drop_if_exists index(:messages, [:conversation_id, :inserted_at])

    drop constraint(:messages, "messages_sender_id_fkey")

    drop constraint(:messages, "messages_conversation_id_fkey")

    drop table(:messages)

    drop constraint(:conversations, "conversations_lessee_id_fkey")

    drop constraint(:conversations, "conversations_lessor_id_fkey")

    drop constraint(:conversations, "conversations_lot_id_fkey")

    drop_if_exists unique_index(:conversations, [:lot_id, :lessee_id],
                     name: "conversations_unique_lot_lessee_index"
                   )

    drop table(:conversations)
  end
end
