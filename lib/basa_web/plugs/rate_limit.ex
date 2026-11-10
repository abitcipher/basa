defmodule BasaWeb.Plugs.RateLimit do
  @behaviour Plug

  @table :basa_rate_limit
  @window_s 60

  def setup do
    if :ets.whereis(@table) == :undefined,
      do: :ets.new(@table, [:named_table, :public, write_concurrency: true])

    :ok
  end

  @impl true
  def init(opts), do: Keyword.put_new(opts, :limit, 120)

  @impl true
  def call(conn, opts) do
    window = div(System.system_time(:second), @window_s)
    bucket = {who(conn), window}
    count = :ets.update_counter(@table, bucket, {2, 1}, {bucket, 0})

    if count == 1,
      do: :ets.select_delete(@table, [{{{:_, :"$1"}, :_}, [{:<, :"$1", window}], [true]}])

    if count > opts[:limit] do
      retry = @window_s - rem(System.system_time(:second), @window_s)

      body =
        Jason.encode!(%{
          errors: [%{status: "429", code: "rate_limited", title: "Too many requests"}]
        })

      conn
      |> Plug.Conn.put_resp_header("retry-after", Integer.to_string(retry))
      |> Plug.Conn.put_resp_content_type("application/vnd.api+json")
      |> Plug.Conn.send_resp(429, body)
      |> Plug.Conn.halt()
    else
      conn
    end
  end

  defp who(conn) do
    case conn.assigns[:current_user] do
      %{__metadata__: %{api_key: %{id: id}}} -> {:key, id}
      %{id: id} -> {:user, id}
      _ -> {:ip, conn.remote_ip}
    end
  end
end
