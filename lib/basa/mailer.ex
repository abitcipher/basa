defmodule Basa.Mailer do
  use Swoosh.Mailer, otp_app: :basa

  require Logger

  def configured? do
    case Application.get_env(:basa, __MODULE__, [])[:adapter] do
      nil -> false
      Swoosh.Adapters.Local -> Application.get_env(:swoosh, :local, true) != false
      _ -> true
    end
  end

  def deliver_if_on(email) do
    if Basa.Services.on?(:email) do
      deliver!(email)
    else
      Logger.info("email is off, skipped #{inspect(email.subject)}")
      {:ok, :skipped}
    end
  end
end
