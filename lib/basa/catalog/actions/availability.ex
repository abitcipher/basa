defmodule Basa.Catalog.Actions.Availability do
  use Ash.Resource.Actions.Implementation

  @impl true
  def run(input, _opts, context) do
    %{lot_id: id, from: from, days: days} = input.arguments

    with {:ok, lot} <- Basa.Catalog.get_lot(id, actor: context.actor) do
      {:ok, Basa.Bookings.Availability.days(lot, from, days)}
    end
  end
end
