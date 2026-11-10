defmodule Basa.Repo.Migrations.TelegramUsers do
  use Ecto.Migration

  def up do
    alter table(:users) do
      modify :email, :citext, null: true
      modify :hashed_password, :text, null: true
    end
  end

  def down do
    alter table(:users) do
      modify :hashed_password, :text, null: false
      modify :email, :citext, null: false
    end
  end
end
