defmodule Basa.Repo.Migrations.WitnessAuthorityRequests do
  use Ecto.Migration

  def up do
    create table(:witness_authority_requests, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :authority, :text, null: false
      add :basis, :text, null: false
      add :reference, :text, null: false
      add :received_on, :date
      add :notes, :text
      add :notify_parties, :boolean, null: false, default: true
      add :no_notice_reason, :text
      add :status, :text, null: false, default: "pending"
      add :decided_at, :utc_datetime_usec
      add :decision_note, :text
      add :parties_notified_at, :utc_datetime_usec
      add :kit_exported_at, :utc_datetime_usec
      add :opened_at, :utc_datetime_usec
      add :key_holders, :text
      add :handed_over_to, :text
      add :report_sha256, :binary

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :updated_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :transaction_id,
          references(:witness_transactions,
            column: :id,
            name: "witness_authority_requests_transaction_id_fkey",
            type: :uuid,
            prefix: "public",
            on_delete: :restrict
          ),
          null: false

      add :filed_by_id,
          references(:users,
            column: :id,
            name: "witness_authority_requests_filed_by_id_fkey",
            type: :uuid,
            prefix: "public"
          )

      add :decided_by_id,
          references(:users,
            column: :id,
            name: "witness_authority_requests_decided_by_id_fkey",
            type: :uuid,
            prefix: "public"
          )
    end
  end

  def down do
    drop constraint(:witness_authority_requests, "witness_authority_requests_decided_by_id_fkey")

    drop constraint(:witness_authority_requests, "witness_authority_requests_filed_by_id_fkey")

    drop constraint(:witness_authority_requests, "witness_authority_requests_transaction_id_fkey")

    drop table(:witness_authority_requests)
  end
end
