defmodule Basa.Moderation.CheckerApi do
  @callback available?() :: boolean()
  @callback check(binary()) :: {:ok, map()} | {:error, term()}
  @callback status() :: {:ok, map()} | {:error, term()}
  @callback set_level(1 | 2) :: {:ok, map()} | {:error, term()}
end
