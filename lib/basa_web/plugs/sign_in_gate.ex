defmodule BasaWeb.Plugs.SignInGate do
  use Gettext, backend: BasaWeb.Gettext
  import Plug.Conn
  import Phoenix.Controller, only: [put_flash: 3, redirect: 2]

  alias Basa.Accounts.SignInMethods

  @methods Map.new(SignInMethods.oauth(), &{to_string(&1), &1})

  def init(opts), do: opts

  def call(%{path_info: ["auth", "user", name | _]} = conn, _opts)
      when is_map_key(@methods, name) do
    if SignInMethods.on?(@methods[name]) do
      conn
    else
      conn
      |> put_flash(:error, gettext("This sign-in option is switched off. Use another one."))
      |> redirect(to: "/sign-in")
      |> halt()
    end
  end

  def call(conn, _opts), do: conn
end
