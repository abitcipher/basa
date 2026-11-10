defmodule Mix.Tasks.Basa.Hyperswitch.Setup do
  @shortdoc "Configures a local Hyperswitch sandbox for BASA and writes the keys to .env"
  use Mix.Task

  @merchant "basa_dev"

  @impl true
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, strict: [url: :string, admin_key: :string])
    Application.ensure_all_started(:req)
    url = opts[:url] || "http://localhost:8080"
    admin = opts[:admin_key] || "test_admin"

    merchant = merchant!(url, admin)
    profile_id = merchant["default_profile"]
    api_key = api_key!(url, admin)
    webhook_key = Base.encode16(:crypto.strong_rand_bytes(32), case: :lower)

    profile!(url, api_key, profile_id, webhook_key)
    connector!(url, api_key, profile_id)

    write_env(%{
      "HYPERSWITCH_URL" => url,
      "HYPERSWITCH_API_KEY" => api_key,
      "HYPERSWITCH_PROFILE_ID" => profile_id,
      "HYPERSWITCH_WEBHOOK_KEY" => webhook_key
    })

    Mix.shell().info(
      "Hyperswitch ready (merchant #{@merchant}, profile #{profile_id}). Restart mix phx.server."
    )
  end

  defp merchant!(url, admin) do
    case post(url, "/accounts", admin, %{merchant_id: @merchant, merchant_name: "BASA (dev)"}) do
      %{status: 200, body: body} -> body
      _exists -> get!(url, "/accounts/#{@merchant}", admin)
    end
  end

  defp api_key!(url, admin) do
    %{status: 200, body: %{"api_key" => key}} =
      post(url, "/api_keys/#{@merchant}", admin, %{
        name: "basa-dev-#{System.os_time(:second)}",
        expiration: "never"
      })

    key
  end

  defp profile!(url, key, profile_id, webhook_key) do
    %{status: 200} =
      post(url, "/account/#{@merchant}/business_profile/#{profile_id}", key, %{
        return_url: "http://localhost:4000/",
        enable_payment_response_hash: true,
        payment_response_hash_key: webhook_key,
        webhook_details: %{
          webhook_url: "http://host.docker.internal:4000/webhooks/hyperswitch",
          payment_statuses_enabled: ["succeeded", "failed", "cancelled", "processing"],
          refund_statuses_enabled: []
        }
      })
  end

  defp connector!(url, key, profile_id) do
    existing = get!(url, "/account/#{@merchant}/connectors", key)

    unless is_list(existing) and Enum.any?(existing, &(&1["connector_name"] == "stripe_test")) do
      card_types =
        for type <- ["credit", "debit"] do
          %{
            payment_method_type: type,
            card_networks: ["Visa", "Mastercard"],
            minimum_amount: 1,
            maximum_amount: 68_607_706,
            recurring_enabled: false,
            installment_payment_enabled: false
          }
        end

      %{status: 200} =
        post(url, "/account/#{@merchant}/connectors", key, %{
          connector_type: "payment_processor",
          connector_name: "stripe_test",
          profile_id: profile_id,
          test_mode: true,
          connector_account_details: %{auth_type: "HeaderKey", api_key: "test_key"},
          payment_methods_enabled: [%{payment_method: "card", payment_method_types: card_types}]
        })
    end
  end

  defp post(url, path, key, body),
    do: Req.post!(url <> path, json: body, headers: [{"api-key", key}], retry: false)

  defp get!(url, path, key),
    do: Req.get!(url <> path, headers: [{"api-key", key}], retry: false).body

  defp write_env(values) do
    lines = if File.exists?(".env"), do: File.read!(".env") |> String.split("\n"), else: []

    lines =
      Enum.reduce(values, lines, fn {k, v}, acc ->
        if Enum.any?(acc, &String.starts_with?(&1, k <> "=")),
          do: Enum.map(acc, &if(String.starts_with?(&1, k <> "="), do: "#{k}=#{v}", else: &1)),
          else: acc ++ ["#{k}=#{v}"]
      end)

    File.write!(".env", Enum.join(lines, "\n"))
  end
end
