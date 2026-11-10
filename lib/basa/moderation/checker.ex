defmodule Basa.Moderation.Checker do
  use GenServer

  require Logger

  @behaviour Basa.Moderation.CheckerApi

  @check_timeout 60_000

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl Basa.Moderation.CheckerApi
  def available? do
    case :persistent_term.get({__MODULE__, :available}, nil) do
      {value, at} when is_boolean(value) ->
        if System.monotonic_time(:second) - at < 60, do: value, else: refresh_available()

      _ ->
        refresh_available()
    end
  end

  defp refresh_available do
    value =
      case image() do
        nil ->
          File.exists?(binary())

        image ->
          docker = System.find_executable("docker")

          docker != nil and
            match?(
              {_, 0},
              System.cmd(docker, ["image", "inspect", "--format", ".", image],
                stderr_to_stdout: true
              )
            )
      end

    :persistent_term.put({__MODULE__, :available}, {value, System.monotonic_time(:second)})
    value
  end

  @impl Basa.Moderation.CheckerApi
  def check(bytes) do
    call(%{op: "check", image: Base.encode64(bytes)}, @check_timeout)
  end

  @impl Basa.Moderation.CheckerApi
  def status, do: call(%{op: "status"}, 10_000)

  @impl Basa.Moderation.CheckerApi
  def set_level(level) do
    call(%{op: "set_level", level: level, phrases: Basa.Moderation.Phrases.all()}, 10_000)
  end

  defp call(request, timeout) do
    GenServer.call(__MODULE__, {:request, request}, timeout + 2_000)
  catch
    :exit, {:timeout, _} -> {:error, :timeout}
    :exit, {:noproc, _} -> {:error, :unavailable}
  end

  @impl true
  def init(_opts), do: {:ok, %{port: nil, next: 1, pending: %{}}}

  @impl true
  def handle_call({:request, request}, from, state) do
    case ensure_port(state) do
      {:ok, state} ->
        {:noreply, send_request(state, request, from)}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_info({port, {:data, data}}, %{port: port} = state) do
    case Jason.decode(data) do
      {:ok, %{"id" => id} = reply} ->
        {from, pending} = Map.pop(state.pending, id)
        if from, do: GenServer.reply(from, result(reply))
        {:noreply, %{state | pending: pending}}

      _ ->
        Logger.warning("basa-moderate sent an unreadable reply")
        {:noreply, state}
    end
  end

  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    Logger.warning("basa-moderate stopped (exit #{status})")
    for {_, from} <- state.pending, from, do: GenServer.reply(from, {:error, :unavailable})
    {:noreply, %{state | port: nil, pending: %{}}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  defp send_request(state, request, from) do
    id = state.next
    Port.command(state.port, Jason.encode!(Map.put(request, :id, id)))
    %{state | next: id + 1, pending: Map.put(state.pending, id, from)}
  end

  defp result(%{"ok" => true, "result" => result}), do: {:ok, result}
  defp result(%{"error" => "not_ready"}), do: {:error, :not_ready}
  defp result(%{"error" => error}), do: {:error, {:checker, error}}

  defp ensure_port(%{port: port} = state) when is_port(port), do: {:ok, state}

  defp ensure_port(state) do
    with {:ok, {executable, args}} <- command() do
      port =
        Port.open({:spawn_executable, executable}, [
          :binary,
          :exit_status,
          {:packet, 4},
          args: args
        ])

      level = Basa.System.settings().moderation_level

      state =
        send_request(
          %{state | port: port},
          %{op: "set_level", level: level, phrases: Basa.Moderation.Phrases.all()},
          nil
        )

      {:ok, state}
    end
  rescue
    e -> {:error, {:checker, Exception.message(e)}}
  end

  @docker_run ~w(run -i --rm --init --read-only --tmpfs /tmp:rw,size=64m --cap-drop=ALL
                 --security-opt=no-new-privileges --memory=2g --pids-limit=256)

  defp command do
    case image() do
      nil ->
        {:ok, {binary(), ["--models", config()[:models_dir] || "priv/models"]}}

      image ->
        docker = System.find_executable("docker")

        if available?() do
          volume = config()[:volume] || "basa_models"

          {:ok,
           {docker,
            @docker_run ++
              ["-v", "#{volume}:/models"] ++ (config()[:docker_args] || []) ++ [image]}}
        else
          {:error, :checker_image_missing}
        end
    end
  end

  defp image do
    case Keyword.get(config(), :docker_image, "basa/moderate:0.1") do
      blank when blank in [nil, ""] -> nil
      image -> image
    end
  end

  defp binary, do: config()[:binary] || Application.app_dir(:basa, "priv/native/basa-moderate")
  defp config, do: Application.get_env(:basa, __MODULE__, [])
end
