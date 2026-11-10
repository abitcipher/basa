defmodule Basa.Payments do
  use Ash.Domain, otp_app: :basa, extensions: [AshTypescript.Rpc]

  typescript_rpc do
    resource Basa.Payments.Payment do
      rpc_action(:admin_payments, :admin_list)
    end
  end

  def enabled?, do: configured?() and Basa.Services.on?(:payments)

  def configured? do
    case Basa.Payments.Gateway.impl() do
      Basa.Payments.Gateway.Hyperswitch ->
        Application.get_env(:basa, Basa.Payments.Gateway.Hyperswitch, [])[:api_key] not in [
          nil,
          ""
        ]

      _other ->
        true
    end
  end

  resources do
    resource Basa.Payments.Payment do
      define :start_commission, action: :start_commission, args: [:booking_id, :amount]
      define :start_premium, action: :start_premium, args: [:lot_id, :product]
      define :list_my_payments, action: :mine
      define :get_payment, action: :read, get_by: [:id]
    end
  end
end
