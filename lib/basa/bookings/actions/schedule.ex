defmodule Basa.Bookings.Actions.Schedule do
  use Ash.Resource.Actions.Implementation
  alias Basa.Bookings.LessorSchedule

  @impl true
  def run(input, opts, %{actor: actor}) when not is_nil(actor) do
    %{from: from, to: to} = input.arguments

    if Date.diff(to, from) > 93 do
      {:error, "the range can be 3 months at most"}
    else
      case opts[:view] do
        :bookings -> {:ok, LessorSchedule.bookings(actor, from, to)}
        :resources -> {:ok, LessorSchedule.resources(actor, from, to)}
        :stats -> {:ok, Basa.Bookings.LessorStats.compute(actor, from, to)}
      end
    end
  end

  def run(_input, _opts, _context), do: {:error, Ash.Error.Forbidden.exception([])}
end
