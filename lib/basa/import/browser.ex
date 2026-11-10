defmodule Basa.Import.Browser do
  use GenServer

  require Logger

  @type rendered :: %{
          url: String.t(),
          status: integer() | nil,
          html: String.t(),
          json: [%{url: String.t(), status: integer(), body: String.t()}],
          load_ms: non_neg_integer(),
          source: String.t() | nil,
          ms: non_neg_integer()
        }

  @default_timeout 30_000

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  def available? do
    Keyword.get(config(), :enabled, true) and
      case image() do
        nil -> File.exists?(binary())
        _ -> System.find_executable("docker") != nil
      end
  end

  @spec render(String.t(), keyword()) :: {:ok, rendered()} | {:error, term()}
  def render(url, opts \\ []) do
    timeout = opts[:timeout] || @default_timeout

    request =
      %{
        op: "render",
        url: url,
        insecure: opts[:insecure] || false,
        timeout_ms: timeout,
        user_agent: opts[:user_agent]
      }
      |> maybe_put(:idle_ms, opts[:idle])
      |> maybe_put(:block, opts[:block])

    if available?(),
      do: GenServer.call(__MODULE__, {:request, request}, timeout + 5_000),
      else: {:error, :browser_unavailable}
  catch
    :exit, {:timeout, _} -> {:error, :timeout}
    :exit, {:noproc, _} -> {:error, :browser_unavailable}
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  @impl true
  def init(_opts), do: {:ok, %{port: nil, next: 1, pending: %{}}}

  @impl true
  def handle_call({:request, request}, from, state) do
    case ensure_port(state) do
      {:ok, state} ->
        id = state.next
        Port.command(state.port, Jason.encode!(Map.put(request, :id, id)))
        {:noreply, %{state | next: id + 1, pending: Map.put(state.pending, id, from)}}

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
        Logger.warning("basa-render sent an unreadable reply")
        {:noreply, state}
    end
  end

  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    Logger.warning("basa-render stopped (exit #{status})")
    for {_, from} <- state.pending, do: GenServer.reply(from, {:error, :browser_exited})
    {:noreply, %{state | port: nil, pending: %{}}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  defp result(%{"ok" => true, "result" => r}) do
    {:ok,
     %{
       url: r["url"],
       status: r["status"],
       html: r["html"],
       json:
         Enum.map(r["json"] || [], &%{url: &1["url"], status: &1["status"], body: &1["body"]}),
       load_ms: r["load_ms"],
       source: r["source"],
       ms: r["ms"]
     }}
  end

  defp result(%{"error" => "private_address"}), do: {:error, :private_address}
  defp result(%{"error" => "timeout"}), do: {:error, :timeout}
  defp result(%{"error" => "too_large"}), do: {:error, :too_large}
  defp result(%{"error" => error}), do: {:error, {:browser, error}}

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

      {:ok, %{state | port: port}}
    end
  rescue
    e -> {:error, {:browser, Exception.message(e)}}
  end

  @docker_run ~w(run -i --rm --init --read-only --tmpfs /tmp:rw,size=256m
                 --tmpfs /home/render:rw,size=64m --shm-size=256m --cap-drop=ALL
                 --security-opt=no-new-privileges --memory=1g --pids-limit=512)

  defp command do
    case image() do
      nil ->
        chrome = config()[:chrome] || System.get_env("CHROME_PATH")
        {:ok, {binary(), if(chrome, do: ["--chrome", chrome], else: []) ++ render_args()}}

      image ->
        docker = System.find_executable("docker")

        case System.cmd(docker, ["image", "inspect", "--format", ".", image],
               stderr_to_stdout: true
             ) do
          {_, 0} ->
            {:ok,
             {docker, @docker_run ++ (config()[:docker_args] || []) ++ [image | render_args()]}}

          _ ->
            {:error, :browser_image_missing}
        end
    end
  end

  defp render_args, do: config()[:args] || []

  defp image do
    case config()[:docker_image] do
      blank when blank in [nil, ""] -> nil
      image -> image
    end
  end

  defp binary, do: config()[:binary] || Application.app_dir(:basa, "priv/native/basa-render")

  defp config, do: Application.get_env(:basa, __MODULE__, [])
end
