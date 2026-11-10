defmodule Basa.Repo.Migrations.QualifiedSignatures do
  use Ecto.Migration

  def up do
    create table(:witness_qualified_signatures, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :role, :text, null: false
      add :provider, :text, null: false
      add :state, :binary, null: false
      add :status, :text, null: false, default: "pending"
      add :failure, :text
      add :cms, :binary
      add :subject, :text
      add :issuer, :text
      add :serial, :text
      add :signing_time, :utc_datetime
      add :test, :boolean, null: false, default: false
      add :name_matches, :boolean
      add :signed_at, :utc_datetime_usec

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :transaction_id,
          references(:witness_transactions,
            column: :id,
            name: "witness_qualified_signatures_transaction_id_fkey",
            type: :uuid,
            prefix: "public",
            on_delete: :delete_all
          ),
          null: false
    end

    create unique_index(:witness_qualified_signatures, [:state],
             name: "witness_qualified_signatures_unique_state_index"
           )

    alter table(:witness_qualified_signatures) do
      add :user_id,
          references(:users,
            column: :id,
            name: "witness_qualified_signatures_user_id_fkey",
            type: :uuid,
            prefix: "public"
          ),
          null: false
    end

    alter table(:witness_transactions) do
      add :qes_signed_at, :utc_datetime_usec
    end
  end

  def down do
    alter table(:witness_transactions) do
      remove :qes_signed_at
    end

    drop constraint(:witness_qualified_signatures, "witness_qualified_signatures_user_id_fkey")

    drop constraint(
           :witness_qualified_signatures,
           "witness_qualified_signatures_transaction_id_fkey"
         )

    alter table(:witness_qualified_signatures) do
      remove :user_id
    end

    drop_if_exists unique_index(:witness_qualified_signatures, [:state],
                     name: "witness_qualified_signatures_unique_state_index"
                   )

    drop table(:witness_qualified_signatures)
  end
end
