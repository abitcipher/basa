defmodule Basa.Repo.Migrations.WitnessContract do
  use Ecto.Migration

  def up do
    alter table(:witness_parties) do
      add :legal_name, :text
    end

    alter table(:witness_transactions) do
      add :languages, {:array, :text}, null: false
      add :deposit_amount, :decimal
      add :claims_window_days, :bigint, null: false, default: 3
      modify :jurisdiction, :text, default: nil
      modify :template, :text, default: nil
    end
  end

  def down do
    alter table(:witness_transactions) do
      modify :template, :text, default: "lease-ua@1"
      modify :jurisdiction, :text, default: "ua"
      remove :claims_window_days
      remove :deposit_amount
      remove :languages
    end

    alter table(:witness_parties) do
      remove :legal_name
    end
  end
end
