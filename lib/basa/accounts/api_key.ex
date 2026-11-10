defmodule Basa.Accounts.ApiKey do
  use Ash.Resource,
    otp_app: :basa,
    domain: Basa.Accounts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "api_keys"
    repo Basa.Repo

    references do
      reference :user, on_delete: :delete
    end
  end

  @max_days 366

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:name, :expires_at]
      change relate_actor(:user)

      change {AshAuthentication.Strategy.ApiKey.GenerateApiKey,
              prefix: :basa, hash: :api_key_hash}
    end

    update :used do
      accept []
      change set_attribute(:last_used_at, &DateTime.utc_now/0)
    end
  end

  policies do
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if always()
    end

    policy action_type(:read) do
      authorize_if relates_to_actor_via(:user)
    end

    policy action(:create) do
      authorize_if actor_present()
    end

    policy action([:create, :destroy]) do
      forbid_if Basa.Accounts.Checks.UsingApiKey
      authorize_if relates_to_actor_via(:user)
      authorize_if action(:create)
    end

    policy action(:used) do
      forbid_if always()
    end
  end

  validations do
    validate string_length(:name, min: 1, max: 80)

    validate &__MODULE__.check_expiry/2, on: [:create]
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false, public?: true, constraints: [trim?: true]

    attribute :api_key_hash, :binary do
      allow_nil? false
      sensitive? true
    end

    attribute :expires_at, :utc_datetime_usec, allow_nil?: false, public?: true
    attribute :last_used_at, :utc_datetime_usec, public?: true
    create_timestamp :inserted_at
  end

  relationships do
    belongs_to :user, Basa.Accounts.User, allow_nil?: false
  end

  calculations do
    calculate :valid, :boolean, expr(expires_at > now())
  end

  identities do
    identity :unique_api_key, [:api_key_hash]
  end

  @doc false
  def check_expiry(changeset, _context) do
    case Ash.Changeset.get_attribute(changeset, :expires_at) do
      nil ->
        :ok

      at ->
        cond do
          DateTime.compare(at, DateTime.utc_now()) != :gt ->
            {:error, field: :expires_at, message: "must be in the future"}

          DateTime.diff(at, DateTime.utc_now(), :day) > @max_days ->
            {:error, field: :expires_at, message: "at most a year ahead"}

          true ->
            :ok
        end
    end
  end
end
