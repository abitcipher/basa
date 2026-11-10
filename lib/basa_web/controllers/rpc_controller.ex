defmodule BasaWeb.RpcController do
  use BasaWeb, :controller

  def run(conn, params), do: json(conn, AshTypescript.Rpc.run_action(:basa, conn, params))

  def validate(conn, params),
    do: json(conn, AshTypescript.Rpc.validate_action(:basa, conn, params))
end
