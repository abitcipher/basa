defmodule Basa.Accounts.User do
  use Ash.Resource,
    otp_app: :basa,
    domain: Basa.Accounts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshAuthentication, AshTypescript.Resource]

  authentication do
    add_ons do
      log_out_everywhere do
        apply_on_password_change? true
      end

      confirmation :confirm_new_user do
        monitor_fields [:email, :facebook_id, :instagram_id]
        confirm_on_create? true
        confirm_on_update? false
        require_interaction? true
        confirmed_at_field :confirmed_at

        auto_confirm_actions [
          :sign_in_with_magic_link,
          :reset_password_with_token,
          :register_with_google,
          :register_with_facebook,
          :register_with_instagram
        ]

        sender Basa.Accounts.User.Senders.SendNewUserConfirmationEmail
      end
    end

    tokens do
      enabled? true
      token_resource Basa.Accounts.Token
      signing_secret Basa.Secrets
      store_all_tokens? true
      require_token_presence_for_authentication? true
    end

    strategies do
      password :password do
        identity_field :email
        hash_provider AshAuthentication.BcryptProvider

        resettable do
          sender Basa.Accounts.User.Senders.SendPasswordResetEmail
          password_reset_action_name :reset_password_with_token
          request_password_reset_action_name :request_password_reset_token
        end
      end

      remember_me :remember_me

      api_key :api_key do
        api_key_relationship :valid_api_keys
        api_key_hash_attribute :api_key_hash
      end

      google do
        client_id Basa.Secrets
        identity_resource Basa.Accounts.UserIdentity
        client_secret Basa.Secrets
        redirect_uri Basa.Secrets
      end

      oauth2 :facebook do
        client_id Basa.Secrets
        identity_resource Basa.Accounts.UserIdentity
        client_secret Basa.Secrets
        redirect_uri Basa.Secrets
        base_url "https://graph.facebook.com"
        authorize_url "https://www.facebook.com/v21.0/dialog/oauth"
        token_url "https://graph.facebook.com/v21.0/oauth/access_token"
        user_url "https://graph.facebook.com/v21.0/me?fields=id,name"
        authorization_params scope: "public_profile"
        auth_method :client_secret_post
        trust_email_verified? false
      end

      oauth2 :instagram do
        client_id Basa.Secrets
        identity_resource Basa.Accounts.UserIdentity
        client_secret Basa.Secrets
        redirect_uri Basa.Secrets
        base_url "https://graph.instagram.com"
        authorize_url "https://www.instagram.com/oauth/authorize"
        token_url "https://api.instagram.com/oauth/access_token"
        user_url "https://graph.instagram.com/v21.0/me?fields=user_id,username"
        authorization_params scope: "instagram_business_basic"
        auth_method :client_secret_post
        trust_email_verified? false
      end
    end
  end

  postgres do
    table "users"
    repo Basa.Repo
  end

  field_policies do
    field_policy_bypass :*, AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if always()
    end

    field_policy [
      :email,
      :phone,
      :telegram_id,
      :facebook_id,
      :instagram_id,
      :instagram_username
    ] do
      authorize_if expr(id == ^actor(:id))
      authorize_if actor_attribute_equals(:role, :admin)
      authorize_if expr(exists(bookings_made, owner_id == ^actor(:id)))
    end

    field_policy :* do
      authorize_if always()
    end
  end

  typescript do
    type_name("User")
  end

  actions do
    defaults [:read]

    read :admin_list do
      pagination offset?: true, required?: false, default_limit: 500, max_page_size: 1000
      prepare build(sort: [display_name: :asc])
    end

    update :update_ui do
      description "Interface preferences (Basa.Accounts.UiPrefs) and the card glow."
      accept [:ui, :glow]
      require_atomic? false

      change fn changeset, _ ->
        case Ash.Changeset.fetch_change(changeset, :ui) do
          {:ok, ui} ->
            Ash.Changeset.force_change_attribute(
              changeset,
              :ui,
              Basa.Accounts.UiPrefs.normalize(ui)
            )

          :error ->
            changeset
        end
      end
    end

    update :update_profile do
      accept [:display_name, :locale, :glow]
    end

    create :sign_in_with_telegram do
      accept [:telegram_id, :telegram_username, :display_name, :locale]
      upsert? true
      upsert_identity :unique_telegram_id
      upsert_fields [:telegram_username]
    end

    create :register_with_google do
      argument :user_info, :map, allow_nil?: false
      argument :oauth_tokens, :map, allow_nil?: false, sensitive?: true
      upsert? true
      upsert_identity :unique_email
      upsert_fields [:email]
      change AshAuthentication.GenerateTokenChange
      change AshAuthentication.Strategy.OAuth2.IdentityChange
      change Basa.Accounts.User.Changes.FromOAuth
    end

    create :register_with_facebook do
      argument :user_info, :map, allow_nil?: false
      argument :oauth_tokens, :map, allow_nil?: false, sensitive?: true
      upsert? true
      upsert_identity :unique_facebook_id
      upsert_fields [:facebook_id]
      change AshAuthentication.GenerateTokenChange
      change AshAuthentication.Strategy.OAuth2.IdentityChange
      change Basa.Accounts.User.Changes.FromOAuth
    end

    create :register_with_instagram do
      argument :user_info, :map, allow_nil?: false
      argument :oauth_tokens, :map, allow_nil?: false, sensitive?: true
      upsert? true
      upsert_identity :unique_instagram_id
      upsert_fields [:instagram_username]
      change AshAuthentication.GenerateTokenChange
      change AshAuthentication.Strategy.OAuth2.IdentityChange
      change Basa.Accounts.User.Changes.FromOAuth
    end

    update :verify_phone_via_telegram do
      accept [:phone]
      change set_attribute(:phone_verified_at, &DateTime.utc_now/0)
    end

    read :get_by_subject do
      description "Get a user by the subject claim in a JWT"
      argument :subject, :string, allow_nil?: false
      get? true
      prepare AshAuthentication.Preparations.FilterBySubject
    end

    update :change_password do
      require_atomic? false
      accept []
      argument :current_password, :string, sensitive?: true, allow_nil?: false

      argument :password, :string,
        sensitive?: true,
        allow_nil?: false,
        constraints: [min_length: 8]

      argument :password_confirmation, :string, sensitive?: true, allow_nil?: false

      validate confirm(:password, :password_confirmation)

      validate {AshAuthentication.Strategy.Password.PasswordValidation,
                strategy_name: :password, password_argument: :current_password}

      change {AshAuthentication.Strategy.Password.HashPasswordChange, strategy_name: :password}
    end

    update :add_password_sign_in do
      require_atomic? false
      accept [:email]

      argument :password, :string,
        sensitive?: true,
        allow_nil?: false,
        constraints: [min_length: 8]

      argument :password_confirmation, :string, sensitive?: true, allow_nil?: false

      validate present(:email)
      validate attribute_equals(:hashed_password, nil), message: "already has a password"
      validate confirm(:password, :password_confirmation)
      change {AshAuthentication.Strategy.Password.HashPasswordChange, strategy_name: :password}
    end

    read :sign_in_with_password do
      description "Attempt to sign in using a email and password."
      get? true

      argument :email, :ci_string do
        description "The email to use for retrieving the user."
        allow_nil? false
      end

      argument :password, :string do
        description "The password to check for the matching user."
        allow_nil? false
        sensitive? true
      end

      prepare AshAuthentication.Strategy.Password.SignInPreparation

      metadata :token, :string do
        description "A JWT that can be used to authenticate the user."
        allow_nil? false
      end
    end

    read :sign_in_with_token do
      description "Attempt to sign in using a short-lived sign in token."
      get? true

      argument :token, :string do
        description "The short-lived sign in token."
        allow_nil? false
        sensitive? true
      end

      prepare AshAuthentication.Strategy.Password.SignInWithTokenPreparation

      metadata :token, :string do
        description "A JWT that can be used to authenticate the user."
        allow_nil? false
      end
    end

    create :register_with_password do
      description "Register a new user with a email and password."

      argument :email, :ci_string do
        allow_nil? false
      end

      argument :password, :string do
        description "The proposed password for the user, in plain text."
        allow_nil? false
        constraints min_length: 8
        sensitive? true
      end

      argument :password_confirmation, :string do
        description "The proposed password for the user (again), in plain text."
        allow_nil? false
        sensitive? true
      end

      change set_attribute(:email, arg(:email))

      change AshAuthentication.Strategy.Password.HashPasswordChange

      change AshAuthentication.GenerateTokenChange

      validate AshAuthentication.Strategy.Password.PasswordConfirmationValidation

      metadata :token, :string do
        description "A JWT that can be used to authenticate the user."
        allow_nil? false
      end
    end

    action :request_password_reset_token do
      description "Send password reset instructions to a user if they exist."

      argument :email, :ci_string do
        allow_nil? false
      end

      run {AshAuthentication.Strategy.Password.RequestPasswordReset, action: :get_by_email}
    end

    read :sign_in_with_api_key do
      argument :api_key, :string, allow_nil?: false
      prepare AshAuthentication.Strategy.ApiKey.SignInPreparation
    end

    read :get_by_email do
      description "Looks up a user by their email"
      get_by :email
    end

    update :reset_password_with_token do
      argument :reset_token, :string do
        allow_nil? false
        sensitive? true
      end

      argument :password, :string do
        description "The proposed password for the user, in plain text."
        allow_nil? false
        constraints min_length: 8
        sensitive? true
      end

      argument :password_confirmation, :string do
        description "The proposed password for the user (again), in plain text."
        allow_nil? false
        sensitive? true
      end

      validate AshAuthentication.Strategy.Password.ResetTokenValidation

      validate AshAuthentication.Strategy.Password.PasswordConfirmationValidation

      change AshAuthentication.Strategy.Password.HashPasswordChange

      change AshAuthentication.GenerateTokenChange
    end
  end

  policies do
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if always()
    end

    policy action(:admin_list) do
      authorize_if actor_attribute_equals(:role, :admin)
    end

    policy action_type(:read) do
      authorize_if expr(id == ^actor(:id))
      authorize_if actor_attribute_equals(:role, :admin)
      authorize_if expr(exists(bookings_made, owner_id == ^actor(:id)))
      authorize_if expr(exists(conversations_as_lessee, lessor_id == ^actor(:id)))
      authorize_if expr(exists(conversations_as_lessor, lessee_id == ^actor(:id)))
    end

    policy action([:update_profile, :update_ui, :add_password_sign_in]) do
      authorize_if expr(id == ^actor(:id))
    end

    policy action([:sign_in_with_telegram, :verify_phone_via_telegram]) do
      forbid_if always()
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :email, :ci_string do
      public? true
    end

    attribute :hashed_password, :string do
      sensitive? true
    end

    attribute :confirmed_at, :utc_datetime_usec

    attribute :display_name, :string, public?: true
    attribute :phone, :string, public?: true
    attribute :phone_verified_at, :utc_datetime_usec
    attribute :telegram_id, :integer, public?: true
    attribute :telegram_username, :string, public?: true
    attribute :facebook_id, :string, public?: true
    attribute :instagram_id, :string, public?: true
    attribute :instagram_username, :string, public?: true

    attribute :locale, :atom do
      constraints one_of: Basa.I18n.atoms()
      default :uk
      allow_nil? false
      public? true
    end

    attribute :ui, :map, default: %{}, allow_nil?: false, public?: true

    attribute :glow, :boolean do
      default true
      allow_nil? false
      public? true
    end

    attribute :role, :atom do
      constraints one_of: [:user, :admin]
      default :user
      allow_nil? false
    end
  end

  relationships do
    has_many :bookings_made, Basa.Bookings.Booking, destination_attribute: :lessee_id

    has_many :valid_api_keys, Basa.Accounts.ApiKey do
      filter expr(valid)
    end

    has_many :conversations_as_lessee, Basa.Messaging.Conversation,
      destination_attribute: :lessee_id

    has_many :conversations_as_lessor, Basa.Messaging.Conversation,
      destination_attribute: :lessor_id
  end

  calculations do
    calculate :has_password, :boolean, expr(not is_nil(hashed_password)), public?: true
  end

  aggregates do
    count :bookings_count, :bookings_made, public?: true
  end

  identities do
    identity :unique_email, [:email]
    identity :unique_telegram_id, [:telegram_id]
    identity :unique_facebook_id, [:facebook_id]
    identity :unique_instagram_id, [:instagram_id]
  end
end
