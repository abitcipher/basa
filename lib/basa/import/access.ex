defmodule Basa.Import.Access do
  use Ash.Resource,
    otp_app: :basa,
    domain: Basa.Import,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias Basa.Import.Agreement

  postgres do
    table "import_access"
    repo Basa.Repo

    references do
      reference :user, on_delete: :delete
    end
  end

  actions do
    defaults [:read]

    create :grant do
      accept []
      argument :user_id, :uuid, allow_nil?: false
      upsert? true
      upsert_identity :unique_user
      upsert_fields [:granted_by_email, :granted_at, :revoked_at]

      change set_attribute(:user_id, arg(:user_id))
      change set_attribute(:granted_at, &DateTime.utc_now/0)
      change set_attribute(:revoked_at, nil)

      change fn changeset, context ->
        Ash.Changeset.force_change_attribute(
          changeset,
          :granted_by_email,
          context.actor && to_string(context.actor.email)
        )
      end
    end

    update :revoke do
      accept []
      change set_attribute(:revoked_at, &DateTime.utc_now/0)
    end

    update :accept do
      require_atomic? false
      accept []
      argument :version, :integer, allow_nil?: false

      change fn changeset, _ ->
        version = Ash.Changeset.get_argument(changeset, :version)

        case Basa.Import.current_agreement() do
          %Agreement{version: ^version} = agreement ->
            changeset
            |> Ash.Changeset.force_change_attribute(:accepted_version, version)
            |> Ash.Changeset.force_change_attribute(:accepted_hash, Agreement.hash(agreement))
            |> Ash.Changeset.force_change_attribute(:accepted_at, DateTime.utc_now())

          _ ->
            Ash.Changeset.add_error(changeset,
              field: :version,
              message: "is not the current agreement"
            )
        end
      end
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if actor_attribute_equals(:role, :admin)
      authorize_if relates_to_actor_via(:user)
    end

    policy action([:grant, :revoke]) do
      authorize_if actor_attribute_equals(:role, :admin)
    end

    policy action(:accept) do
      authorize_if expr(user_id == ^actor(:id) and is_nil(revoked_at))
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :granted_by_email, :string, public?: true
    attribute :granted_at, :utc_datetime_usec, allow_nil?: false, public?: true
    attribute :revoked_at, :utc_datetime_usec, public?: true
    attribute :accepted_version, :integer, public?: true
    attribute :accepted_hash, :string, public?: true
    attribute :accepted_at, :utc_datetime_usec, public?: true
    timestamps()
  end

  relationships do
    belongs_to :user, Basa.Accounts.User, allow_nil?: false, public?: true
  end

  identities do
    identity :unique_user, [:user_id]
  end
end
