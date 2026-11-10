defmodule Basa.Catalog.Preparations.FreeOn do
  use Ash.Resource.Preparation

  @impl true
  def prepare(query, _opts, _context) do
    case Ash.Query.get_argument(query, :free_on) do
      nil ->
        query

      date ->
        Ash.Query.after_action(query, fn _query, lots ->
          {:ok, Enum.filter(lots, &free_on?(&1, date))}
        end)
    end
  end

  defp free_on?(lot, date) do
    case Basa.Bookings.Availability.days(lot, date, 1) do
      [%{free: free}] -> free > 0
      _ -> false
    end
  end
end
