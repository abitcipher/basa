defmodule Basa.Events.Changes.Publish do
  use Ash.Resource.Change
  alias Basa.Events.External

  @impl true
  def change(changeset, opts, _context) do
    {field, prefix, data_fun} =
      case opts[:kind] do
        :booking -> {:status, "booking", &External.booking_data/1}
        :lot -> {:state, "lot", &External.lot_data/1}
      end

    before = Map.get(changeset.data, field)
    created? = changeset.action_type == :create

    Ash.Changeset.after_transaction(changeset, fn
      _cs, {:ok, record} ->
        value = Map.fetch!(record, field)

        if created? or value != before,
          do: External.publish("#{prefix}.#{value}", data_fun.(record))

        {:ok, record}

      _cs, other ->
        other
    end)
  end

  @impl true
  def atomic(changeset, opts, context), do: {:ok, change(changeset, opts, context)}
end
