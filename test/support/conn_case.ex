defmodule BasaWeb.ConnCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      @endpoint BasaWeb.Endpoint

      use BasaWeb, :verified_routes

      import Plug.Conn
      import Phoenix.ConnTest
      import BasaWeb.ConnCase
    end
  end

  setup tags do
    Basa.DataCase.setup_sandbox(tags)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  def sign_in(conn, user) do
    {:ok, token, _claims} = AshAuthentication.Jwt.token_for_user(user)
    user = Ash.Resource.put_metadata(user, :token, token)

    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> AshAuthentication.Plug.Helpers.store_in_session(user)
  end
end
