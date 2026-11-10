defmodule Basa.Repo.Migrations.WitnessCore do
  use Ecto.Migration

  def up do
    create table(:witness_access_logs, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :action, :text, null: false
      add :reason, :text
      add :reference, :text
      add :result, :text, null: false

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :transaction_id, :uuid, null: false

      add :actor_id,
          references(:users,
            column: :id,
            name: "witness_access_logs_actor_id_fkey",
            type: :uuid,
            prefix: "public"
          )
    end

    create table(:witness_evidence, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :position, :bigint, null: false
      add :kind, :text, null: false
      add :media_type, :text, null: false
      add :size, :bigint, null: false
      add :sha256, :binary, null: false
      add :storage_key, :text, null: false

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :updated_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :transaction_id, :uuid, null: false
    end

    create unique_index(:witness_evidence, [:transaction_id, :sha256],
             name: "witness_evidence_unique_file_index"
           )

    create unique_index(:witness_evidence, [:transaction_id, :position],
             name: "witness_evidence_unique_position_index"
           )

    alter table(:witness_evidence) do
      add :added_by_id,
          references(:users,
            column: :id,
            name: "witness_evidence_added_by_id_fkey",
            type: :uuid,
            prefix: "public"
          )
    end

    create table(:witness_key_shares, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :owner, :text, null: false
      add :share, :binary, null: false
      add :delivered_at, :utc_datetime_usec

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :updated_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :transaction_id, :uuid, null: false
    end

    create unique_index(:witness_key_shares, [:transaction_id, :owner],
             name: "witness_key_shares_one_per_owner_index"
           )

    create table(:witness_parties, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :role, :text, null: false
      add :public_key, :binary
      add :signature, :binary
      add :signed_at, :utc_datetime_usec

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :updated_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :transaction_id, :uuid, null: false
    end

    create unique_index(:witness_parties, [:transaction_id, :role],
             name: "witness_parties_one_per_role_index"
           )

    alter table(:witness_parties) do
      add :user_id,
          references(:users,
            column: :id,
            name: "witness_parties_user_id_fkey",
            type: :uuid,
            prefix: "public"
          ),
          null: false
    end

    create table(:witness_transactions, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
    end

    alter table(:witness_access_logs) do
      modify :transaction_id,
             references(:witness_transactions,
               column: :id,
               name: "witness_access_logs_transaction_id_fkey",
               type: :uuid,
               prefix: "public",
               on_delete: :restrict
             )
    end

    alter table(:witness_evidence) do
      modify :transaction_id,
             references(:witness_transactions,
               column: :id,
               name: "witness_evidence_transaction_id_fkey",
               type: :uuid,
               prefix: "public",
               on_delete: :delete_all
             )
    end

    alter table(:witness_key_shares) do
      modify :transaction_id,
             references(:witness_transactions,
               column: :id,
               name: "witness_key_shares_transaction_id_fkey",
               type: :uuid,
               prefix: "public",
               on_delete: :delete_all
             )
    end

    alter table(:witness_parties) do
      modify :transaction_id,
             references(:witness_transactions,
               column: :id,
               name: "witness_parties_transaction_id_fkey",
               type: :uuid,
               prefix: "public",
               on_delete: :delete_all
             )
    end

    alter table(:witness_transactions) do
      add :contract_type, :text, null: false, default: "lease"
      add :jurisdiction, :text, null: false, default: "ua"
      add :consumer, :boolean, null: false, default: false
      add :template, :text, null: false, default: "lease-ua@1"
      add :status, :text, null: false, default: "draft"
      add :storage_mode, :text, null: false
      add :recovery_sealed, :binary, null: false
      add :manifest, :binary
      add :basa_hash, :binary
      add :sealed_at, :utc_datetime_usec

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :updated_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :booking_id,
          references(:bookings,
            column: :id,
            name: "witness_transactions_booking_id_fkey",
            type: :uuid,
            prefix: "public",
            on_delete: :restrict
          ),
          null: false
    end

    create unique_index(:witness_transactions, [:booking_id],
             name: "witness_transactions_one_per_booking_index"
           )

    create unique_index(:witness_transactions, [:basa_hash],
             name: "witness_transactions_unique_basa_hash_index"
           )
  end

  def down do
    drop constraint(:witness_transactions, "witness_transactions_booking_id_fkey")

    drop_if_exists unique_index(:witness_transactions, [:basa_hash],
                     name: "witness_transactions_unique_basa_hash_index"
                   )

    drop_if_exists unique_index(:witness_transactions, [:booking_id],
                     name: "witness_transactions_one_per_booking_index"
                   )

    alter table(:witness_transactions) do
      remove :booking_id
      remove :updated_at
      remove :inserted_at
      remove :sealed_at
      remove :basa_hash
      remove :manifest
      remove :recovery_sealed
      remove :storage_mode
      remove :status
      remove :template
      remove :consumer
      remove :jurisdiction
      remove :contract_type
    end

    drop constraint(:witness_parties, "witness_parties_user_id_fkey")

    drop constraint(:witness_parties, "witness_parties_transaction_id_fkey")

    alter table(:witness_parties) do
      modify :transaction_id, :uuid
    end

    drop constraint(:witness_key_shares, "witness_key_shares_transaction_id_fkey")

    alter table(:witness_key_shares) do
      modify :transaction_id, :uuid
    end

    drop constraint(:witness_evidence, "witness_evidence_added_by_id_fkey")

    drop constraint(:witness_evidence, "witness_evidence_transaction_id_fkey")

    alter table(:witness_evidence) do
      modify :transaction_id, :uuid
    end

    drop constraint(:witness_access_logs, "witness_access_logs_actor_id_fkey")

    drop constraint(:witness_access_logs, "witness_access_logs_transaction_id_fkey")

    alter table(:witness_access_logs) do
      modify :transaction_id, :uuid
    end

    drop table(:witness_transactions)

    alter table(:witness_parties) do
      remove :user_id
    end

    drop_if_exists unique_index(:witness_parties, [:transaction_id, :role],
                     name: "witness_parties_one_per_role_index"
                   )

    drop table(:witness_parties)

    drop_if_exists unique_index(:witness_key_shares, [:transaction_id, :owner],
                     name: "witness_key_shares_one_per_owner_index"
                   )

    drop table(:witness_key_shares)

    alter table(:witness_evidence) do
      remove :added_by_id
    end

    drop_if_exists unique_index(:witness_evidence, [:transaction_id, :position],
                     name: "witness_evidence_unique_position_index"
                   )

    drop_if_exists unique_index(:witness_evidence, [:transaction_id, :sha256],
                     name: "witness_evidence_unique_file_index"
                   )

    drop table(:witness_evidence)

    drop table(:witness_access_logs)
  end
end
