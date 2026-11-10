defmodule Basa.OpenverseStub do
  @fixture Path.expand("fixtures/openverse/microphone.json", __DIR__)
  @external_resource @fixture

  def recorded, do: @fixture |> File.read!() |> Jason.decode!()

  def jpeg(seed), do: <<0xFF, 0xD8, 0xFF, 0xE0>> <> seed

  def stub(pid \\ self(), opts \\ []) do
    Req.Test.stub(Basa.Images, fn conn ->
      url = "#{conn.scheme}://#{conn.host}#{conn.request_path}"

      case conn.host do
        "api.openverse.org" ->
          conn = Plug.Conn.fetch_query_params(conn)
          send(pid, {:openverse, conn.query_params})

          case opts[:search] do
            nil -> Req.Test.json(conn, recorded())
            status when is_integer(status) -> Plug.Conn.send_resp(conn, status, "")
            body -> Req.Test.json(conn, body)
          end

        _ ->
          send(pid, {:download, url})

          case opts[:download] do
            nil -> Plug.Conn.send_resp(conn, 200, opts[:same_bytes] || jpeg(url))
            fun when is_function(fun, 1) -> fun.(conn)
          end
      end
    end)
  end

  def candidates, do: for(r <- recorded()["results"], do: r)
end
