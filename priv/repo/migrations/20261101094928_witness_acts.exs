defmodule Basa.Repo.Migrations.WitnessActs do
  use Ecto.Migration

  def up do
    create table(:witness_acts, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :kind, :text, null: false
      add :author, :text, null: false
      add :author_user_id, :uuid
      add :status, :text, null: false, default: "draft"
      add :terms, :map, null: false, default: %{}
      add :sequence, :bigint
      add :bytes, :binary
      add :hash, :binary
      add :previous, :binary
      add :author_signature, :binary
      add :counter_signature, :binary
      add :effective_at, :utc_datetime_usec

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :updated_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :transaction_id,
          references(:witness_transactions,
            column: :id,
            name: "witness_acts_transaction_id_fkey",
            type: :uuid,
            prefix: "public",
            on_delete: :delete_all
          ),
          null: false
    end

    create unique_index(:witness_acts, [:transaction_id, :sequence],
             name: "witness_acts_one_place_in_chain_index"
           )

    drop_if_exists unique_index(:witness_evidence, [:transaction_id, :position],
                     name: "witness_evidence_unique_position_index"
                   )

    alter table(:witness_evidence) do
      add :act_id,
          references(:witness_acts,
            column: :id,
            name: "witness_evidence_act_id_fkey",
            type: :uuid,
            prefix: "public"
          )
    end

    create unique_index(:witness_evidence, [:transaction_id, :act_id, :position],
             name: "witness_evidence_unique_position_index",
             nulls_distinct: false
           )

    alter table(:witness_transactions) do
      add :returned_at, :utc_datetime_usec
      add :claims_until, :utc_datetime_usec
      add :closed_at, :utc_datetime_usec
      add :deposit_status, :text, null: false, default: "none"
      add :deposit_kept, :decimal
    end
  end

  def down do
    alter table(:witness_transactions) do
      remove :deposit_kept
      remove :deposit_status
      remove :closed_at
      remove :claims_until
      remove :returned_at
    end

    drop constraint(:witness_evidence, "witness_evidence_act_id_fkey")

    drop_if_exists unique_index(:witness_evidence, [:transaction_id, :act_id, :position],
                     name: "witness_evidence_unique_position_index"
                   )

    alter table(:witness_evidence) do
      remove :act_id
    end

    create unique_index(:witness_evidence, [:transaction_id, :position],
             name: "witness_evidence_unique_position_index"
           )

    drop constraint(:witness_acts, "witness_acts_transaction_id_fkey")

    drop_if_exists unique_index(:witness_acts, [:transaction_id, :sequence],
                     name: "witness_acts_one_place_in_chain_index"
                   )

    drop table(:witness_acts)
  end
end
