defmodule BasaWeb.TelegramController do
  use BasaWeb, :controller
  import AshAuthentication.Plug.Helpers

  alias Basa.Accounts.TelegramSignIn

  def app(conn, params) do
    conn
    |> put_root_layout(html: {BasaWeb.Layouts, :root})
    |> assign(:telegram_webapp, true)
    |> render(:app, to: BasaTma.safe_path(params["to"]))
  end

  def webapp_sign_in(conn, %{"init_data" => init_data} = params) do
    with true <- Basa.Accounts.SignInMethods.on?(:telegram),
         {:ok, tg_user} <- Basa.Telegram.verify_init_data(init_data),
         {:ok, user} <- TelegramSignIn.sign_in(Basa.Telegram.user_attrs(tg_user)) do
      conn
      |> store_in_session(user)
      |> put_session(:locale, to_string(user.locale))
      |> BasaTma.Plug.enter()
      |> json(%{ok: true, to: BasaTma.safe_path(params["to"])})
    else
      _ -> conn |> put_status(401) |> json(%{ok: false})
    end
  end

  def widget_sign_in(conn, params) do
    fields = Map.take(params, ~w(id first_name last_name username photo_url auth_date hash))

    with true <- Basa.Accounts.SignInMethods.on?(:telegram) || :off,
         {:ok, data} <- Basa.Telegram.verify_login_widget(fields),
         {:ok, user} <- TelegramSignIn.sign_in(Basa.Telegram.user_attrs(data)) do
      conn
      |> store_in_session(user)
      |> put_flash(:info, gettext("Signed in with Telegram."))
      |> redirect(to: ~p"/my")
    else
      :off ->
        conn
        |> put_flash(
          :error,
          gettext(
            "Sign-in with Telegram is switched off for now. Sign in with your email and password."
          )
        )
        |> redirect(to: ~p"/sign-in")

      _ ->
        conn
        |> put_flash(:error, gettext("Telegram sign-in failed."))
        |> redirect(to: ~p"/sign-in")
    end
  end
end
