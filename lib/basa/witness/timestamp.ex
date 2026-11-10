defmodule Basa.Witness.Timestamp do
  @callback stamp(hash :: binary()) ::
              {:ok, %{token: binary(), time: DateTime.t()}} | {:error, term()}
  @callback verify(token :: binary(), hash :: binary()) :: {:ok, DateTime.t()} | {:error, term()}

  def stamp(hash), do: impl().stamp(hash)
  def verify(token, hash), do: impl().verify(token, hash)

  def config, do: Application.get_env(:basa, __MODULE__, [])

  def configured?, do: impl() != nil

  def enabled?, do: configured?() and Basa.Services.on?(:timestamp)
  defp impl, do: Keyword.get(config(), :impl, Basa.Witness.Timestamp.RFC3161)
end
