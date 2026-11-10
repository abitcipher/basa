import Config

config :basa, Oban, testing: :manual
config :basa, token_signing_secret: "+Jg8Eyaq9Ty/4wPbxXfJAjAkYSEm6ccf"
config :bcrypt_elixir, log_rounds: 1

config :ash,
  policies: [show_policy_breakdowns?: true],
  keyset_signing_secret: "Rah6xkjUZdVN2uvROeNgwDQKfUA5Q1Klm1q7B3Frw9I",
  disable_async?: true

config :basa, Basa.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "basa_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

config :basa, BasaWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "MzrWnZ1xzDKVTIvUbyCQ9rd8hg+iVcg/go9hSYCGffPvN4SsnNQu2W3GZLuTn6ff",
  server: false

config :basa, Basa.Mailer, adapter: Swoosh.Adapters.Test

config :swoosh, :api_client, false

config :logger, level: :warning

config :phoenix, :plug_init_mode, :runtime

config :phoenix_live_view,
  enable_expensive_runtime_checks: true

config :phoenix,
  sort_verified_routes_query_params: true

config :basa, Basa.Storage,
  adapter: Basa.Storage.Local,
  root: Path.join(System.tmp_dir!(), "basa-media-test")

config :basa, :payment_gateway, Basa.Payments.Gateway.Fake

config :basa, :sync_rules_on_boot, false

config :basa, Basa.Geo.Photon, req_options: [plug: {Req.Test, Basa.Geo.Photon}]

config :basa, Basa.Images, req_options: [plug: {Req.Test, Basa.Images}], check_hosts: false
config :basa, Basa.Images.Openverse, cache: false
config :basa, Basa.Import, req_options: [plug: {Req.Test, Basa.Import}], check_hosts: false

config :basa, Basa.StreetView,
  token: "test-token",
  req_options: [plug: {Req.Test, Basa.StreetView}]

config :basa, Basa.Import.Browser, enabled: false, args: ["--allow-private"]

config :basa, :widgets_enabled_default, false

config :basa, Basa.Witness.QES, providers: [:dev]

config :basa, Basa.Witness.QES.CscProvider,
  service_url: "http://csc.test/csc/v2",
  oauth_url: "http://csc.test/oauth2",
  client_id: "basa-test",
  client_secret: "test",
  anchors: {BasaWeb.Dev.CscEmulator, :anchors, []},
  test: true,
  req_options: [plug: {Req.Test, Basa.Witness.QES.CscProvider}]

config :basa, Basa.Witness.QES.Dss, req_options: [plug: {Req.Test, Basa.Witness.QES.Dss}]

config :basa, Basa.Witness,
  storage_mode: :plain,
  recovery_public_key:
    Base.decode16!("e35ab3538152835e3916486aa25d5e5414e94a7c76c3a983f340172399c24220",
      case: :lower
    ),
  recovery_private_key:
    Base.decode16!("502b30e568bf2ef1efe6db373df23bb1b0e5cc5259562006bbb6e9bdbbc98a41",
      case: :lower
    )

config :basa, Basa.Witness.Timestamp, impl: Basa.Witness.Timestamp.Fake
config :basa, Basa.Moderation, checker: Basa.ModerationStub
