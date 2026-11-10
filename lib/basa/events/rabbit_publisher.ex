defmodule Basa.Events.RabbitPublisher do
  use GenServer
  require Logger

  @exchange "basa.events"
  @confirm_timeout 5_000

  def exchange, do: @exchange

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  def publish(routing_key, body, meta) do
    GenServer.call(__MODULE__, {:publish, routing_key, body, meta}, @confirm_timeout + 1_000)
  catch
    :exit, reason -> {:error, {:publisher_unavailable, reason}}
  end

  @impl true
  def init(opts) do
    {:ok, %{url: Keyword.fetch!(opts, :url), conn: nil, chan: nil, backoff: 1_000},
     {:continue, :connect}}
  end

  @impl true
  def handle_continue(:connect, state), do: {:noreply, connect(state)}

  @impl true
  def handle_info(:connect, state), do: {:noreply, connect(state)}

  def handle_info({:DOWN, _, :process, _pid, reason}, state) do
    Logger.warning("RabbitMQ connection lost: #{inspect(reason)}; reconnecting")
    send(self(), :connect)
    {:noreply, %{state | conn: nil, chan: nil}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def handle_call({:publish, _key, _body, _meta}, _from, %{chan: nil} = state) do
    {:reply, {:error, :not_connected}, state}
  end

  def handle_call({:publish, key, body, meta}, _from, %{chan: chan} = state) do
    opts = [
      persistent: true,
      content_type: "application/json",
      message_id: meta[:id],
      type: key,
      timestamp: System.system_time(:second),
      app_id: "basa"
    ]

    reply =
      with :ok <- AMQP.Basic.publish(chan, @exchange, key, body, opts),
           true <- AMQP.Confirm.wait_for_confirms(chan, @confirm_timeout) do
        :ok
      else
        false -> {:error, :nacked}
        :timeout -> {:error, :confirm_timeout}
        error -> error
      end

    {:reply, reply, state}
  end

  @impl true
  def terminate(_reason, %{conn: conn}) when not is_nil(conn), do: AMQP.Connection.close(conn)
  def terminate(_reason, _state), do: :ok

  defp connect(state) do
    with {:ok, conn} <- AMQP.Connection.open(state.url, name: "basa"),
         {:ok, chan} <- AMQP.Channel.open(conn),
         :ok <- AMQP.Confirm.select(chan),
         :ok <- AMQP.Exchange.declare(chan, @exchange, :topic, durable: true) do
      Process.monitor(conn.pid)
      Logger.info("RabbitMQ connected; publishing to #{@exchange}")
      %{state | conn: conn, chan: chan, backoff: 1_000}
    else
      error ->
        Logger.warning(
          "RabbitMQ connect failed (#{inspect(error)}); retry in #{state.backoff} ms"
        )

        Process.send_after(self(), :connect, state.backoff)
        %{state | backoff: min(state.backoff * 2, 30_000)}
    end
  end
end
