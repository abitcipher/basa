defmodule BasaWeb.Plugs.ApiAuth do
  @behaviour Plug

  @impl true
  def init(_opts) do
    AshAuthentication.Strategy.ApiKey.Plug.init(
      resource: Basa.Accounts.User,
      required?: false,
      on_error: &__MODULE__.on_error/2
    )
  end

  @impl true
  def call(conn, config), do: AshAuthentication.Strategy.ApiKey.Plug.call(conn, config)

  @doc false
  def on_error(%{assigns: %{current_user: %{}}} = conn, _error), do: conn

  def on_error(conn, _error) do
    body =
      Jason.encode!(%{
        errors: [%{status: "401", code: "invalid_api_key", title: "Invalid or expired API key"}]
      })

    conn
    |> Plug.Conn.put_resp_content_type("application/vnd.api+json")
    |> Plug.Conn.send_resp(401, body)
    |> Plug.Conn.halt()
  end
end
