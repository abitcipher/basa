defmodule Basa.System.Settings do
  use Ash.Resource,
    otp_app: :basa,
    domain: Basa.System,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "system_settings"
    repo Basa.Repo
  end

  actions do
    defaults [:read]

    create :create do
      accept []
    end

    update :update do
      require_atomic? false

      accept [
        :widgets_enabled,
        :services_off,
        :near_control,
        :near_steps_km,
        :near_city,
        :near_region,
        :near_default,
        :sign_in_off,
        :moderation_level
      ]

      validate Basa.System.Validations.NearSteps
      change Basa.Rules.Changes.Stamp
      change Basa.System.Changes.CatchUp
      change Basa.Moderation.Changes.LevelChanged
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if always()
    end

    policy action(:update) do
      authorize_if actor_attribute_equals(:role, :admin)
    end

    policy action(:create) do
      forbid_if always()
    end
  end

  attributes do
    attribute :id, :string,
      primary_key?: true,
      allow_nil?: false,
      default: "global",
      public?: true

    attribute :widgets_enabled, :boolean,
      allow_nil?: false,
      public?: true,
      default: &__MODULE__.widgets_default/0

    attribute :services_off, {:array, :atom},
      allow_nil?: false,
      public?: true,
      default: [],
      constraints: [items: [one_of: Basa.Services.all()]]

    attribute :near_control, :atom,
      allow_nil?: false,
      public?: true,
      default: :slider,
      constraints: [one_of: [:slider, :chips, :select]]

    attribute :near_steps_km, {:array, :integer},
      allow_nil?: false,
      public?: true,
      default: [1, 10, 25, 75, 125],
      constraints: [items: [min: 1, max: 2000], max_length: 12]

    attribute :near_city, :boolean, allow_nil?: false, public?: true, default: true
    attribute :near_region, :boolean, allow_nil?: false, public?: true, default: true
    attribute :near_default, :string, allow_nil?: false, public?: true, default: "25"

    attribute :sign_in_off, {:array, :atom},
      allow_nil?: false,
      public?: true,
      default: [],
      constraints: [items: [one_of: Basa.Accounts.SignInMethods.all()]]

    attribute :moderation_level, :integer,
      allow_nil?: false,
      public?: true,
      default: 1,
      constraints: [min: 1, max: 2]

    attribute :updated_by_email, :string, public?: true
    timestamps()
  end

  def widgets_default, do: Application.get_env(:basa, :widgets_enabled_default, true)
end
