import Config

config :ash,
  policies: [show_policy_breakdowns?: true],
  keyset_signing_secret: "n86ERXpBFA4zXyyqEDKl8yrYpq08M5/B8HpidxqASlY"

config :basa, Basa.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "basa_dev",
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

config :basa, BasaWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "2P0PupAyJO24eWh7vcuqoVtP/THh13V/2wK89PBgPBSGc37DOPlWBsDkdjkFcn1M",
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:basa, ~w(--sourcemap=inline --watch)]},
    tailwind: {Tailwind, :install_and_run, [:basa, ~w(--watch)]},
    npm: ["run", "watch", cd: Path.expand("../assets/widgets", __DIR__)]
  ]

config :basa, dev_routes: true, token_signing_secret: "Q8hZ8fHPIquUWaEiCC4dcSvQF/KPHqfh"

config :logger, :default_formatter, format: "[$level] $message\n"

config :phoenix, :stacktrace_depth, 20

config :phoenix, :plug_init_mode, :runtime

config :phoenix_live_view,
  debug_heex_annotations: true,
  debug_attributes: true,
  enable_expensive_runtime_checks: true

config :swoosh, :api_client, false

config :basa, Basa.Storage,
  adapter: Basa.Storage.S3,
  endpoint: "http://localhost:9000",
  bucket: "basa-media",
  access_key: "basa",
  secret_key: "basa-secret"

config :basa, Basa.Search, url: "http://localhost:7700", key: "basa-dev-master-key-change-me"

config :basa, Basa.Witness.QES, providers: [:dev, :csc]

config :basa, Basa.Witness.QES.CscProvider,
  service_url: "http://localhost:4000/dev/csc/csc/v2",
  oauth_url: "http://localhost:4000/dev/csc/oauth2",
  client_id: "basa-dev",
  client_secret: "dev",
  anchors: {BasaWeb.Dev.CscEmulator, :anchors, []},
  test: true

config :basa, Basa.Witness.QES.Dss, url: "http://localhost:8095"

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
