defmodule Basa.Payments.Gateway do
  @type checkout :: %{provider_payment_id: String.t(), payment_url: String.t()}
  @type status :: :pending | :succeeded | :failed | :cancelled | :expired

  @callback create_checkout(map()) :: {:ok, checkout()} | {:error, term()}
  @callback fetch_status(provider_payment_id :: String.t()) :: {:ok, status()} | {:error, term()}
  @callback verify_webhook(raw_body :: binary(), signature :: String.t() | nil) ::
              :ok | {:error, :invalid_signature}

  def impl, do: Application.get_env(:basa, :payment_gateway, Basa.Payments.Gateway.Hyperswitch)
  def create_checkout(params), do: impl().create_checkout(params)
  def fetch_status(id), do: impl().fetch_status(id)
  def verify_webhook(body, sig), do: impl().verify_webhook(body, sig)
end
