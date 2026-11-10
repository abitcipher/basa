import Config

config :basa, :env, config_env()

config :basa, Basa.Witness, storage_mode: :encrypted, recovery_public_key: nil

config :basa, Basa.Witness.Timestamp,
  impl: Basa.Witness.Timestamp.RFC3161,
  url: "https://freetsa.org/tsr",
  certificates: "freetsa"

config :mime,
  extensions: %{"json" => "application/vnd.api+json"},
  types: %{"application/vnd.api+json" => ["json"]}

config :ash_json_api,
  show_public_calculations_when_loaded?: false,
  authorize_update_destroy_with_error?: true

config :ash_oban, pro?: false

config :basa, Oban,
  engine: Oban.Engines.Basic,
  notifier: Oban.Notifiers.Postgres,
  queues: [default: 10, ai: 4, notifications: 10, events: 5, import: 2, moderation: 1],
  lifeline: [rescue_after: {2, :hours}],
  pruner: [max_age: {1, :day}],
  repo: Basa.Repo,
  cron: [crontab: [{"30 3 * * *", Basa.Import.RefreshWorker}]]

config :ash,
  allow_forbidden_field_for_relationships_by_default: true,
  include_embedded_source_by_default?: false,
  show_keysets_for_all_actions?: false,
  default_page_type: :keyset,
  policies: [no_filter_static_forbidden_reads?: false],
  keep_read_action_loads_when_loading?: false,
  default_actions_require_atomic?: true,
  read_action_after_action_hooks_in_order?: true,
  bulk_actions_default_to_errors?: true,
  transaction_rollback_on_error?: true,
  redact_sensitive_values_in_errors?: true,
  default_string_length_count: :codepoints,
  infer_generic_action_reactors?: false,
  many_to_many_destroy_destination_on_match?: true,
  known_types: [AshPostgres.Timestamptz, AshPostgres.TimestamptzUsec]

config :spark,
  formatter: [
    remove_parens?: true,
    "Ash.Resource": [
      section_order: [
        :json_api,
        :authentication,
        :token,
        :user_identity,
        :postgres,
        :resource,
        :code_interface,
        :actions,
        :policies,
        :pub_sub,
        :preparations,
        :changes,
        :validations,
        :multitenancy,
        :attributes,
        :relationships,
        :calculations,
        :aggregates,
        :identities
      ]
    ],
    "Ash.Domain": [
      section_order: [:json_api, :resources, :policies, :authorization, :domain, :execution]
    ]
  ]

config :basa,
  ecto_repos: [Basa.Repo],
  generators: [timestamp_type: :utc_datetime, binary_id: true],
  ash_domains: [
    Basa.Witness,
    Basa.System,
    Basa.Accounts,
    Basa.Geo,
    Basa.Catalog,
    Basa.Bookings,
    Basa.Messaging,
    Basa.Payments,
    Basa.Rules,
    Basa.Images,
    Basa.Import,
    Basa.Moderation
  ]

config :basa, BasaWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: BasaWeb.ErrorHTML, json: BasaWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Basa.PubSub,
  live_view: [signing_salt: "YTljFZAx"]

config :phoenix_live_view,
  root_tag_attribute: "phx-r"

config :basa, Basa.Mailer, adapter: Swoosh.Adapters.Local

config :ash_typescript,
  manifest: Basa.AshTypescriptManifest,
  output_file: "assets/widgets/src/ash_rpc.ts",
  run_endpoint: "/rpc/run",
  validate_endpoint: "/rpc/validate",
  input_field_formatter: :camel_case,
  output_field_formatter: :camel_case,
  warn_on_non_rpc_references: false

config :esbuild,
  version: "0.25.4",
  basa: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

config :tailwind,
  version: "4.3.3",
  basa: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :phoenix, :json_library, Jason

import_config "#{config_env()}.exs"

config :elixir, :time_zone_database, Tzdata.TimeZoneDatabase

config :basa, :telegram, bot_token: nil, bot_username: nil
config :ex_gram, adapter: ExGram.Adapter.Req
