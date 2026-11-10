defmodule Basa.Rules.Changes.ValidateGraph do
  use Ash.Resource.Change

  alias RulesEngine, as: Engine

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      case Engine.validate(Ash.Changeset.get_attribute(changeset, :graph)) do
        :ok -> changeset
        {:error, message} -> Ash.Changeset.add_error(changeset, field: :graph, message: message)
      end
    end)
  end
end
