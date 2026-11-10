defmodule Basa.Accounts.UserIdentity do
  use Ash.Resource,
    otp_app: :basa,
    domain: Basa.Accounts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshAuthentication.UserIdentity]

  user_identity do
    user_resource Basa.Accounts.User
  end

  postgres do
    table "user_identities"
    repo Basa.Repo
  end

  policies do
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if always()
    end

    policy always() do
      forbid_if always()
    end
  end
end
