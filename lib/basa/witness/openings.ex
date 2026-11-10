defmodule Basa.Witness.Openings do
  use GenServer

  @table __MODULE__
  @ttl_ms 60_000

  def start_link(_), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  def put(user_id, scope, share) when is_binary(share) do
    ticket = 24 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
    :ets.insert(@table, {ticket, user_id, scope, share, now() + @ttl_ms})
    ticket
  end

  def take(ticket, user_id, scope) when is_binary(ticket) do
    case :ets.take(@table, ticket) do
      [{^ticket, ^user_id, ^scope, share, until}] -> if now() < until, do: share
      _ -> nil
    end
  end

  def take(_ticket, _user_id, _scope), do: nil

  @impl true
  def init(nil) do
    :ets.new(@table, [:set, :public, :named_table, read_concurrency: true])
    schedule()
    {:ok, nil}
  end

  @impl true
  def handle_info(:sweep, state) do
    :ets.select_delete(@table, [{{:_, :_, :_, :_, :"$1"}, [{:<, :"$1", now()}], [true]}])
    schedule()
    {:noreply, state}
  end

  defp schedule, do: Process.send_after(self(), :sweep, @ttl_ms)
  defp now, do: System.monotonic_time(:millisecond)
end
