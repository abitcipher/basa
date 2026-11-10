import Config

if System.get_env("PHX_SERVER") do
  config :basa, BasaWeb.Endpoint, server: true
end

config :basa, BasaWeb.Endpoint, http: [port: String.to_integer(System.get_env("PORT", "4000"))]

if config_env() == :dev and File.exists?(".env") do
  for line <- File.stream!(".env"),
      line = String.trim(line),
      line != "" and not String.starts_with?(line, "#"),
      [key, value] <- [String.split(line, "=", parts: 2)],
      System.get_env(key) in [nil, ""] do
    System.put_env(key, value)
  end
end

if config_env() == :prod do
  config :basa, Basa.Witness,
    storage_mode: :encrypted,
    recovery_public_key:
      (case System.get_env("WITNESS_RECOVERY_PUBLIC_KEY") do
         nil -> nil
         hex -> Base.decode16!(String.downcase(hex), case: :lower)
       end)
end

if config_env() != :test do
  config :basa, :telegram,
    bot_token: System.get_env("TELEGRAM_BOT_TOKEN"),
    bot_username: System.get_env("TELEGRAM_BOT_USERNAME"),
    webhook_secret: System.get_env("TELEGRAM_WEBHOOK_SECRET"),
    updates: if(config_env() == :prod, do: :webhook, else: :polling)

  config :basa, :anthropic_api_key, System.get_env("ANTHROPIC_API_KEY")

  config :basa, Basa.Accounts.SignInMethods,
    google: [
      client_id: System.get_env("GOOGLE_CLIENT_ID"),
      client_secret: System.get_env("GOOGLE_CLIENT_SECRET")
    ],
    facebook: [
      client_id: System.get_env("FACEBOOK_APP_ID"),
      client_secret: System.get_env("FACEBOOK_APP_SECRET")
    ],
    instagram: [
      client_id: System.get_env("INSTAGRAM_APP_ID"),
      client_secret: System.get_env("INSTAGRAM_APP_SECRET")
    ]

  if api_key = System.get_env("HYPERSWITCH_API_KEY") do
    config :basa, Basa.Payments.Gateway.Hyperswitch,
      url: System.get_env("HYPERSWITCH_URL", "http://localhost:8080"),
      api_key: api_key,
      profile_id: System.get_env("HYPERSWITCH_PROFILE_ID"),
      webhook_key: System.get_env("HYPERSWITCH_WEBHOOK_KEY")
  end

  rabbit_url =
    System.get_env("RABBITMQ_URL") ||
      if(config_env() == :dev, do: "amqp://basa:basa@localhost:5672")

  if rabbit_url do
    config :basa, :external_publisher, Basa.Events.RabbitPublisher
    config :basa, Basa.Events.RabbitPublisher, url: rabbit_url
  end

  if config_env() == :dev and System.get_env("TELEGRAM_BOT_TOKEN") in [nil, ""] and
       System.get_env("TELEGRAM_EMULATOR") != "false" do
    config :basa, :telegram,
      bot_token: BasaTma.Emulator.token(),
      bot_username: BasaTma.Emulator.bot_username(),
      updates: :emulator

    config :basa_tma, :emulator, Basa.Telegram.emulator_options()
    config :ex_gram, adapter: BasaTma.Emulator.Adapter
  end
end

if config_env() == :dev do
  config :basa, BasaWeb.Endpoint,
    live_reload: [
      web_console_logger: true,
      patterns: [
        ~r"priv/static/(?!uploads/).*\.(js|css|png|jpeg|jpg|gif|svg)$"E,
        ~r"priv/gettext/.*\.po$"E,
        ~r"lib/basa_web/router\.ex$"E,
        ~r"lib/basa_web/(controllers|live|components)/.*\.(ex|heex)$"E
      ]
    ]
end

if config_env() != :test do
  config :basa, :widgets_enabled_default, System.get_env("WIDGETS_ENABLED", "true") != "false"
end

if config_env() != :test do
  config :basa, Basa.Geo.Photon,
    photon_url: System.get_env("PHOTON_URL", "https://photon.komoot.io"),
    nominatim_url: System.get_env("NOMINATIM_URL", "https://nominatim.openstreetmap.org"),
    contact: System.get_env("GEO_CONTACT")
end

if config_env() != :test do
  config :basa, Basa.Import, user_agent: System.get_env("IMPORT_USER_AGENT")

  config :basa, Basa.Import.Browser,
    docker_image: System.get_env("RENDER_IMAGE", "basa/render:0.1"),
    chrome: System.get_env("CHROME_PATH"),
    args: String.split(System.get_env("RENDER_ARGS", ""))
end

if config_env() != :test do
  config :basa, Basa.Images, contact: System.get_env("IMAGES_CONTACT")

  config :basa, Basa.Images.Openverse,
    url: System.get_env("OPENVERSE_URL", "https://api.openverse.org")
end

if config_env() != :test do
  config :basa, Basa.StreetView, token: System.get_env("MAPILLARY_TOKEN")
end

if config_env() == :prod do
  config :basa, Basa.Witness.QES.Dss, url: System.get_env("DSS_URL", "http://dss:8080")

  config :basa, Basa.Search,
    url: System.get_env("MEILI_URL", "http://meilisearch:7700"),
    key: System.fetch_env!("MEILI_MASTER_KEY")

  config :basa, Basa.Storage,
    adapter: Basa.Storage.S3,
    endpoint: System.get_env("S3_ENDPOINT", "http://rustfs:9000"),
    bucket: System.get_env("S3_BUCKET", "basa-media"),
    stock_bucket: System.get_env("S3_STOCK_BUCKET", "basa-stock"),
    access_key: System.fetch_env!("S3_ACCESS_KEY"),
    secret_key: System.fetch_env!("S3_SECRET_KEY")

  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :basa, Basa.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    socket_options: maybe_ipv6

  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"

  config :basa, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :basa, BasaWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base

  config :ash,
    keyset_signing_secret:
      :crypto.mac(
        :hmac,
        :sha256,
        System.get_env("SECRET_KEY_BASE") ||
          raise("environment variable SECRET_KEY_BASE is missing"),
        "ash keyset signing"
      )

  config :basa,
    token_signing_secret:
      System.get_env("TOKEN_SIGNING_SECRET") ||
        raise("Missing environment variable `TOKEN_SIGNING_SECRET`!")
end
