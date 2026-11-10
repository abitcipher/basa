defmodule Basa.Geo.Changes.Reindex do
  use Ash.Resource.Change

  @impl true
  def change(%{context: %{skip_reindex: true}} = changeset, _opts, _context), do: changeset

  def change(changeset, _opts, _context) do
    Ash.Changeset.after_transaction(changeset, fn
      _cs, {:ok, city} ->
        Basa.Geo.IndexWorker.enqueue([city.id])
        {:ok, city}

      _cs, other ->
        other
    end)
  end

  @impl true
  def atomic(changeset, opts, context), do: {:ok, change(changeset, opts, context)}
end
