defmodule Basa.Accounts do
  use Ash.Domain,
    otp_app: :basa,
    extensions: [AshTypescript.Rpc]

  typescript_rpc do
    resource Basa.Accounts.User do
      rpc_action(:admin_users, :admin_list)
    end
  end

  resources do
    resource Basa.Accounts.Token
    resource Basa.Accounts.UserIdentity

    resource Basa.Accounts.ApiKey do
      define :create_api_key, action: :create, args: [:name, :expires_at]
      define :list_api_keys, action: :read
      define :revoke_api_key, action: :destroy
    end

    resource Basa.Accounts.User do
      define :update_profile, action: :update_profile
      define :add_password_sign_in, action: :add_password_sign_in
      define :update_ui, action: :update_ui
    end
  end
end
