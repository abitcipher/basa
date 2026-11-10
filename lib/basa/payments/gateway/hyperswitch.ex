defmodule Basa.Payments.Gateway.Hyperswitch do
  @behaviour Basa.Payments.Gateway
  require Logger

  @impl true
  def create_checkout(%{amount: amount, currency: currency} = p) do
    body = %{
      amount: minor_units(amount),
      currency: to_string(currency),
      payment_link: true,
      description: p[:description],
      return_url: p[:return_url],
      customer_id: p[:customer_id],
      profile_id: config()[:profile_id],
      session_expiry: 3600,
      metadata: %{basa_payment_id: p[:reference]}
    }

    case request(:post, "/payments", body) do
      {:ok, %{status: 200, body: %{"payment_id" => id, "payment_link" => %{"link" => link}}}} ->
        {:ok, %{provider_payment_id: id, payment_url: link}}

      {:ok, %{status: status, body: body}} ->
        Logger.warning("Hyperswitch create payment failed: #{status} #{inspect(body)}")
        {:error, {:http, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def fetch_status(id) do
    case request(:get, "/payments/#{URI.encode(id)}", nil) do
      {:ok, %{status: 200, body: %{"status" => status}}} -> {:ok, map_status(status)}
      {:ok, %{status: status}} -> {:error, {:http, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def verify_webhook(_body, nil), do: {:error, :invalid_signature}

  def verify_webhook(body, signature) do
    expected =
      :crypto.mac(:hmac, :sha512, config()[:webhook_key] || "", body)
      |> Base.encode16(case: :lower)

    if Plug.Crypto.secure_compare(expected, String.downcase(signature)),
      do: :ok,
      else: {:error, :invalid_signature}
  end

  def map_status("succeeded"), do: :succeeded
  def map_status(s) when s in ~w(failed), do: :failed
  def map_status(s) when s in ~w(cancelled cancelled_post_capture), do: :cancelled
  def map_status("expired"), do: :expired
  def map_status(_), do: :pending

  defp minor_units(%Decimal{} = amount),
    do: amount |> Decimal.mult(100) |> Decimal.round(0) |> Decimal.to_integer()

  defp request(method, path, body) do
    [
      method: method,
      url: config()[:url] <> path,
      headers: [{"api-key", config()[:api_key] || ""}],
      retry: :transient,
      receive_timeout: 15_000
    ]
    |> then(&if(is_nil(body), do: &1, else: Keyword.put(&1, :json, body)))
    |> Req.request()
  rescue
    e -> {:error, e}
  end

  defp config, do: Application.get_env(:basa, __MODULE__, [])
end
