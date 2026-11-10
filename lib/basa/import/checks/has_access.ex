defmodule Basa.Import.Checks.HasAccess do
  use Ash.Policy.SimpleCheck

  @impl true
  def describe(_), do: "actor may use the import tool"

  @impl true
  def match?(actor, _context, _opts), do: Basa.Import.allowed?(actor)
end
