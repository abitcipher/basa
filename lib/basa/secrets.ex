defmodule Basa.Secrets do
  use AshAuthentication.Secret

  def secret_for([:authentication, :tokens, :signing_secret], Basa.Accounts.User, _opts, _context) do
    Application.fetch_env(:basa, :token_signing_secret)
  end

  def secret_for([:authentication, :strategies, method, :redirect_uri], _, _, _)
      when method in [:google, :facebook, :instagram],
      do: {:ok, BasaWeb.Endpoint.url() <> "/auth"}

  def secret_for([:authentication, :strategies, method, key], _, _, _)
      when method in [:google, :facebook, :instagram] and key in [:client_id, :client_secret] do
    case Basa.Accounts.SignInMethods.config(method)[key] do
      value when value not in [nil, ""] -> {:ok, value}
      _ -> :error
    end
  end
end
