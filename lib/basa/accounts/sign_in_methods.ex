defmodule Basa.Accounts.SignInMethods do
  @methods [:google, :facebook, :instagram, :telegram]
  @oauth [:google, :facebook, :instagram]

  def all, do: @methods

  def oauth, do: @oauth

  def on?(:telegram), do: Basa.Telegram.enabled?() and not switched_off?(:telegram)
  def on?(method) when method in @oauth, do: configured?(method) and not switched_off?(method)

  def available, do: Enum.filter(@methods, &on?/1)

  def switched_off?(method) when method in @methods,
    do: method in Basa.System.settings().sign_in_off

  def configured?(:telegram), do: Basa.Telegram.configured?()

  def configured?(method) when method in @oauth do
    keys = config(method)
    keys[:client_id] not in [nil, ""] and keys[:client_secret] not in [nil, ""]
  end

  def config(method), do: Application.get_env(:basa, __MODULE__, [])[method] || []
end
