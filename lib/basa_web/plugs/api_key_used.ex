defmodule BasaWeb.Plugs.ApiKeyUsed do
  @behaviour Plug

  @every_s 600

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    case conn.assigns[:current_user] do
      %{__metadata__: %{using_api_key?: true, api_key: key}} ->
        if is_nil(key.last_used_at) or
             DateTime.diff(DateTime.utc_now(), key.last_used_at) > @every_s,
           do: Ash.update(key, %{}, action: :used, authorize?: false)

        conn

      _ ->
        conn
    end
  end
end
