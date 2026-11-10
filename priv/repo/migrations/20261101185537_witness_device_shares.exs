defmodule Basa.Repo.Migrations.WitnessDeviceShares do
  use Ecto.Migration

  def up do
    alter table(:witness_acts) do
      add :recovery_sealed, :binary
    end

    alter table(:witness_evidence) do
      add :stored_sha256, :binary
    end

    drop_if_exists unique_index(:witness_key_shares, [:transaction_id, :owner],
                     name: "witness_key_shares_one_per_owner_index"
                   )

    alter table(:witness_key_shares) do
      add :sealed_share, :binary

      add :act_id,
          references(:witness_acts,
            column: :id,
            name: "witness_key_shares_act_id_fkey",
            type: :uuid,
            prefix: "public"
          )
    end

    create unique_index(:witness_key_shares, [:transaction_id, :act_id, :owner],
             name: "witness_key_shares_one_per_owner_index",
             nulls_distinct: false
           )

    alter table(:witness_key_shares) do
      modify :share, :binary, null: true
    end

    alter table(:witness_parties) do
      add :box_key, :binary
    end
  end

  def down do
    alter table(:witness_parties) do
      remove :box_key
    end

    drop constraint(:witness_key_shares, "witness_key_shares_act_id_fkey")

    alter table(:witness_key_shares) do
      modify :share, :binary, null: false
    end

    drop_if_exists unique_index(:witness_key_shares, [:transaction_id, :act_id, :owner],
                     name: "witness_key_shares_one_per_owner_index"
                   )

    alter table(:witness_key_shares) do
      remove :act_id
      remove :sealed_share
    end

    create unique_index(:witness_key_shares, [:transaction_id, :owner],
             name: "witness_key_shares_one_per_owner_index"
           )

    alter table(:witness_evidence) do
      remove :stored_sha256
    end

    alter table(:witness_acts) do
      remove :recovery_sealed
    end
  end
end
