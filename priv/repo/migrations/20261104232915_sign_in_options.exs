defmodule Basa.Repo.Migrations.SignInOptions do
  use Ecto.Migration

  def up do
    alter table(:system_settings) do
      add :sign_in_off, {:array, :text}, null: false, default: []
    end

    alter table(:users) do
      add :facebook_id, :text
      add :instagram_id, :text
      add :instagram_username, :text
    end

    create unique_index(:users, [:facebook_id], name: "users_unique_facebook_id_index")

    create unique_index(:users, [:instagram_id], name: "users_unique_instagram_id_index")

    create table(:user_identities, primary_key: false) do
      add :refresh_token, :text
      add :access_token_expires_at, :utc_datetime_usec
      add :access_token, :text
      add :uid, :text, null: false
      add :strategy, :text, null: false
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true

      add :user_id,
          references(:users,
            column: :id,
            name: "user_identities_user_id_fkey",
            type: :uuid,
            prefix: "public"
          )
    end

    create unique_index(:user_identities, [:strategy, :uid],
             name: "user_identities_unique_on_strategy_and_uid_index"
           )
  end

  def down do
    drop constraint(:user_identities, "user_identities_user_id_fkey")

    drop_if_exists unique_index(:user_identities, [:strategy, :uid],
                     name: "user_identities_unique_on_strategy_and_uid_index"
                   )

    drop table(:user_identities)

    drop_if_exists unique_index(:users, [:instagram_id], name: "users_unique_instagram_id_index")

    drop_if_exists unique_index(:users, [:facebook_id], name: "users_unique_facebook_id_index")

    alter table(:users) do
      remove :instagram_username
      remove :instagram_id
      remove :facebook_id
    end

    alter table(:system_settings) do
      remove :sign_in_off
    end
  end
end
