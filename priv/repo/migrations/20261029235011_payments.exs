defmodule Basa.Repo.Migrations.Payments do
  use Ecto.Migration

  def up do
    alter table(:lots) do
      add :featured_until, :utc_datetime_usec
    end

    create table(:payments, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :purpose, :text, null: false
      add :product, :text
      add :amount, :decimal, null: false
      add :currency, :text, null: false
      add :status, :text, null: false, default: "pending"
      add :provider_payment_id, :text
      add :payment_url, :text
      add :paid_at, :utc_datetime_usec

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :updated_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :user_id,
          references(:users,
            column: :id,
            name: "payments_user_id_fkey",
            type: :uuid,
            prefix: "public",
            on_delete: :restrict
          ),
          null: false

      add :booking_id,
          references(:bookings,
            column: :id,
            name: "payments_booking_id_fkey",
            type: :uuid,
            prefix: "public",
            on_delete: :nilify_all
          )

      add :lot_id,
          references(:lots,
            column: :id,
            name: "payments_lot_id_fkey",
            type: :uuid,
            prefix: "public",
            on_delete: :nilify_all
          )
    end

    create index(:payments, [:provider_payment_id], unique: true)

    create index(:payments, [:user_id, :inserted_at])
  end

  def down do
    drop_if_exists index(:payments, [:user_id, :inserted_at])

    drop_if_exists index(:payments, [:provider_payment_id])

    drop constraint(:payments, "payments_lot_id_fkey")

    drop constraint(:payments, "payments_booking_id_fkey")

    drop constraint(:payments, "payments_user_id_fkey")

    drop table(:payments)

    alter table(:lots) do
      remove :featured_until
    end
  end
end
