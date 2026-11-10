defmodule Basa.Search.Changes.Reindex do
  use Ash.Resource.Change
  require Ash.Query

  @impl true
  def change(changeset, opts, _context) do
    case opts[:lots] do
      :self ->
        Ash.Changeset.after_transaction(changeset, fn
          _changeset, {:ok, lot} ->
            Basa.Search.IndexWorker.enqueue([lot.id])
            {:ok, lot}

          _changeset, other ->
            other
        end)

      how ->
        changeset
        |> Ash.Changeset.before_action(fn cs ->
          Ash.Changeset.put_context(cs, :reindex_lot_ids, lot_ids(cs.data, how))
        end)
        |> Ash.Changeset.after_transaction(fn
          cs, {:ok, record} ->
            Basa.Search.IndexWorker.enqueue(cs.context[:reindex_lot_ids] || [])
            {:ok, record}

          _cs, other ->
            other
        end)
    end
  end

  @impl true
  def atomic(changeset, opts, context), do: {:ok, change(changeset, opts, context)}

  defp lot_ids(record, :by_basket) do
    Basa.Catalog.Lot |> Ash.Query.filter(basket_id == ^record.id) |> ids()
  end

  defp lot_ids(record, :by_room) do
    Basa.Catalog.Lot |> Ash.Query.filter(room_id == ^record.id) |> ids()
  end

  defp lot_ids(record, :by_item) do
    Basa.Catalog.Lot |> Ash.Query.filter(exists(basket.items, id == ^record.id)) |> ids()
  end

  defp ids(query),
    do: query |> Ash.Query.select([:id]) |> Ash.read!(authorize?: false) |> Enum.map(& &1.id)
end
