defmodule Basa.Import.Actions.Shared do
  @moduledoc false
  alias Basa.Import

  def own_source(id, actor) do
    case Import.get_source(id, actor: actor) do
      {:ok, %{owner_id: owner} = source} when owner == actor.id -> {:ok, source}
      {:ok, _} -> {:error, Ash.Error.Forbidden.exception([])}
      error -> error
    end
  end

  def import_on do
    if Import.enabled?(), do: :ok, else: invalid(:id, "importing is switched off")
  end

  def invalid(field, message),
    do: {:error, Ash.Error.Changes.InvalidArgument.exception(field: field, message: message)}
end
