defmodule Basa.Repo.Migrations.MemAttestations do
  use Ecto.Migration

  def up do
    create table(:witness_mem_attestations, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :role, :text, null: false
      add :challenge, :binary, null: false
      add :status, :text, null: false, default: "pending"
      add :attestation, :binary
      add :statement, :binary
      add :attest_key, :binary
      add :via, :text
      add :received_at, :utc_datetime_usec

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :transaction_id,
          references(:witness_transactions,
            column: :id,
            name: "witness_mem_attestations_transaction_id_fkey",
            type: :uuid,
            prefix: "public",
            on_delete: :delete_all
          ),
          null: false
    end

    create unique_index(:witness_mem_attestations, [:challenge],
             name: "witness_mem_attestations_unique_challenge_index"
           )

    alter table(:witness_mem_attestations) do
      add :user_id,
          references(:users,
            column: :id,
            name: "witness_mem_attestations_user_id_fkey",
            type: :uuid,
            prefix: "public"
          ),
          null: false
    end

    alter table(:witness_transactions) do
      add :mem_confirmed_at, :utc_datetime_usec
    end
  end

  def down do
    alter table(:witness_transactions) do
      remove :mem_confirmed_at
    end

    drop constraint(:witness_mem_attestations, "witness_mem_attestations_user_id_fkey")

    drop constraint(:witness_mem_attestations, "witness_mem_attestations_transaction_id_fkey")

    alter table(:witness_mem_attestations) do
      remove :user_id
    end

    drop_if_exists unique_index(:witness_mem_attestations, [:challenge],
                     name: "witness_mem_attestations_unique_challenge_index"
                   )

    drop table(:witness_mem_attestations)
  end
end
