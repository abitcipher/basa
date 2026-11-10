defmodule BasaWeb.Router do
  use BasaWeb, :router

  use AshAuthentication.Phoenix.Router

  import AshAuthentication.Plug.Helpers

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {BasaWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :load_from_session
    plug BasaWeb.Plugs.Locale
    plug BasaTma.Plug
    plug BasaWeb.Plugs.SignInGate
  end

  pipeline :rpc do
    plug :accepts, ["json"]
    plug :fetch_session
    plug :protect_from_forgery
    plug :load_from_session
    plug :set_actor, :user
    plug BasaWeb.Plugs.Locale
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug :load_from_bearer
    plug BasaWeb.Plugs.ApiAuth
    plug :set_actor, :user
    plug BasaWeb.Plugs.ApiKeyUsed
    plug BasaWeb.Plugs.RateLimit
  end

  scope "/api/json" do
    pipe_through [:api]

    forward "/swaggerui", OpenApiSpex.Plug.SwaggerUI,
      path: "/api/json/open_api",
      default_model_expand_depth: 4

    forward "/", BasaWeb.AshJsonApiRouter
  end

  scope "/webhooks", BasaWeb do
    pipe_through :api
    post "/hyperswitch", PaymentController, :webhook
  end

  scope "/mem", BasaWeb do
    post "/attest/:token", MemAttestController, :create
  end

  scope "/rpc", BasaWeb do
    pipe_through :rpc
    post "/run", RpcController, :run
    post "/validate", RpcController, :validate
  end

  scope "/", BasaWeb do
    pipe_through :browser

    get "/media/*key", MediaController, :show
    get "/payments/:id/return", PaymentController, :return
    get "/transactions/:id/evidence/:position", EvidenceController, :show
    get "/transactions/:id/acts/:act_id/files/:position", EvidenceController, :show
    get "/transactions/:id/disclose/:position", EvidenceController, :disclose
    get "/admin/witness/requests/:id/kit", EvidenceController, :recovery_kit
    get "/qes/return/:token", QesController, :return

    get "/tg", TelegramController, :app
    post "/auth/telegram/webapp", TelegramController, :webapp_sign_in
    get "/auth/telegram/widget", TelegramController, :widget_sign_in

    ash_authentication_live_session :public,
      on_mount: [
        {BasaWeb.Plugs.Locale, :default},
        {BasaWeb.LiveUserAuth, :live_user_optional},
        BasaWeb.UnreadHook,
        BasaWeb.WidgetsHook
      ] do
      live "/", HomeLive, :index
      live "/lots/:id", LotLive, :show
      live "/verify", VerifyLive, :index
      live "/help", HelpLive, :index
      live "/help/:topic", HelpLive, :show
      live "/app", AppHomeLive, :index
    end

    ash_authentication_live_session :signed_in,
      on_mount: [
        {BasaWeb.Plugs.Locale, :default},
        {BasaWeb.LiveUserAuth, :live_user_required},
        BasaWeb.UnreadHook,
        BasaWeb.WidgetsHook
      ] do
      live "/bookings", BookingsLive, :index
      live "/transactions/:id", TransactionLive, :show
      live "/profile", ProfileLive, :edit
      live "/appearance", AppearanceLive, :edit
      live "/messages", MessagesLive, :index
      live "/messages/:id", MessagesLive, :show

      live "/my", My.DashboardLive, :index
      live "/my/schedule", My.ScheduleLive, :index
      live "/my/stats", My.StatsLive, :index
      live "/my/photos", My.PhotosLive, :index
      live "/my/items", My.ItemsLive, :index
      live "/my/items/new", My.ItemsLive, :new
      live "/my/items/:id", My.ItemsLive, :show
      live "/my/items/:id/edit", My.ItemsLive, :edit
      live "/my/baskets/new", My.BasketWizardLive, :new
      live "/my/baskets/:id/edit", My.BasketWizardLive, :edit
      live "/my/rooms/new", My.RoomWizardLive, :new
      live "/my/rooms/:id/edit", My.RoomWizardLive, :edit
      live "/my/lots/new", My.LotWizardLive, :new
      live "/my/lots/:id/edit", My.LotWizardLive, :edit
      live "/my/import", My.ImportLive, :index
      live "/my/import/:id", My.ImportSourceLive, :edit

      live "/admin/review", Admin.ReviewLive, :index
      live "/admin/rules", Admin.RulesLive, :index
      live "/admin/rules/:key", Admin.RuleEditorLive, :edit
      live "/admin/geo", Admin.GeoLive, :index
      live "/admin/settings", Admin.SettingsLive, :index
      live "/admin/photos", Admin.PhotosLive, :index
      live "/admin/import", Admin.ImportLive, :index
      live "/admin/data", Admin.DataLive, :index
      live "/admin/witness", Admin.WitnessLive, :index
      live "/admin/witness/:id", Admin.WitnessLive, :show
    end
  end

  scope "/", BasaWeb do
    pipe_through :browser

    auth_routes AuthController, Basa.Accounts.User, path: "/auth"

    sign_out_route AuthController, "/sign-out",
      overrides: [BasaWeb.AuthOverrides, AshAuthentication.Phoenix.Overrides.Default]

    sign_in_route register_path: "/register",
                  live_view: BasaWeb.SignInLive,
                  reset_path: "/reset",
                  auth_routes_prefix: "/auth",
                  on_mount: [{BasaWeb.LiveUserAuth, :live_no_user}],
                  overrides: [BasaWeb.AuthOverrides, AshAuthentication.Phoenix.Overrides.Default]

    reset_route auth_routes_prefix: "/auth",
                overrides: [BasaWeb.AuthOverrides, AshAuthentication.Phoenix.Overrides.Default]

    confirm_route Basa.Accounts.User, :confirm_new_user,
      auth_routes_prefix: "/auth",
      overrides: [BasaWeb.AuthOverrides, AshAuthentication.Phoenix.Overrides.Default]

    magic_sign_in_route(Basa.Accounts.User, :magic_link,
      auth_routes_prefix: "/auth",
      overrides: [BasaWeb.AuthOverrides, AshAuthentication.Phoenix.Overrides.Default]
    )
  end

  if Application.compile_env(:basa, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live "/telegram", BasaTma.Emulator.Live
      get "/telegram/file/:id", BasaTma.Emulator.File, :show
    end

    scope "/dev", BasaWeb.Dev do
      pipe_through :browser

      ash_authentication_live_session :dev_qes,
        on_mount: [
          {BasaWeb.Plugs.Locale, :default},
          {BasaWeb.LiveUserAuth, :live_user_required},
          BasaWeb.UnreadHook
        ] do
        live "/qes/:token", QesLive, :show
      end
    end

    scope "/dev" do
      forward "/csc", BasaWeb.Dev.CscEmulator
    end

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: BasaWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
