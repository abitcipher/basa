defmodule Basa.Repo.Migrations.WitnessFilePerAct do
  use Ecto.Migration

  def up do
    drop_if_exists unique_index(:witness_evidence, [:transaction_id, :sha256],
                     name: "witness_evidence_unique_file_index"
                   )

    create unique_index(:witness_evidence, [:transaction_id, :act_id, :sha256],
             name: "witness_evidence_unique_file_index",
             nulls_distinct: false
           )
  end

  def down do
    drop_if_exists unique_index(:witness_evidence, [:transaction_id, :act_id, :sha256],
                     name: "witness_evidence_unique_file_index"
                   )

    create unique_index(:witness_evidence, [:transaction_id, :sha256],
             name: "witness_evidence_unique_file_index"
           )
  end
end
