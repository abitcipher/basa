defmodule Basa.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    BasaWeb.Plugs.RateLimit.setup()

    Basa.Witness.check_config!()

    children =
      [
        BasaWeb.Telemetry,
        Basa.Repo,
        {Oban,
         AshOban.config(
           Application.fetch_env!(:basa, :ash_domains),
           Application.fetch_env!(:basa, Oban)
         )},
        {DNSCluster, query: Application.get_env(:basa, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: Basa.PubSub},
        Basa.Geo.Photon,
        Basa.Images.Openverse,
        Basa.Import.Browser,
        Basa.Moderation.Checker,
        Basa.Witness.Openings,
        BasaWeb.Endpoint,
        {AshAuthentication.Supervisor, [otp_app: :basa]},
        {Task, fn -> Basa.Storage.ensure_bucket() end},
        Supervisor.child_spec({Task, fn -> Basa.Search.setup() end}, id: :search_setup),
        Supervisor.child_spec({Task, fn -> Basa.Geo.Index.setup() end}, id: :geo_index_setup),
        Supervisor.child_spec({Task, fn -> Basa.Images.Index.setup() end},
          id: :images_index_setup
        ),
        Supervisor.child_spec({Task, &sync_rules/0}, id: :rules_sync)
      ] ++ events_children() ++ telegram_children()

    opts = [strategy: :one_for_one, name: Basa.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    BasaWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp sync_rules do
    if Application.get_env(:basa, :sync_rules_on_boot, true), do: Basa.Rules.Library.sync()
  end

  defp events_children do
    case Application.get_env(:basa, Basa.Events.RabbitPublisher) do
      nil -> []
      opts -> [{Basa.Events.RabbitPublisher, opts}]
    end
  end

  defp telegram_children do
    config = Application.get_env(:basa, :telegram, [])

    if config[:bot_token] in [nil, ""] do
      []
    else
      case config[:updates] do
        :emulator ->
          [
            ExGram,
            BasaTma.Emulator,
            {Basa.Telegram.Bot, [method: :test, token: config[:bot_token], handler_mode: :sync]}
          ]

        _ ->
          real_bot(config)
      end
    end
  end

  defp real_bot(config) do
    method =
      case config[:updates] do
        :webhook ->
          {:webhook,
           [
             url: BasaWeb.Endpoint.url(),
             path: "/telegram",
             secret_token: config[:webhook_secret],
             allowed_updates: ["message", "callback_query"]
           ]}

        _ ->
          {:polling, allowed_updates: ["message", "callback_query"]}
      end

    [ExGram, {Basa.Telegram.Bot, [method: method, token: config[:bot_token]]}]
  end
end
