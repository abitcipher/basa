defmodule BasaWeb.TelegramControllerTest do
  use BasaWeb.ConnCase, async: false

  @token "123456:TEST-TOKEN"

  setup do
    previous = Application.get_env(:basa, :telegram)
    Application.put_env(:basa, :telegram, bot_token: @token)
    on_exit(fn -> Application.put_env(:basa, :telegram, previous) end)
  end

  defp init_data(user), do: BasaTma.Auth.sign_init_data(user, @token)

  test "Mini App sign-in creates the user and opens the requested page", %{conn: conn} do
    data = init_data(%{id: 777, first_name: "Olena", language_code: "uk"})
    conn = post(conn, ~p"/auth/telegram/webapp", %{init_data: data, to: "/my"})

    assert %{"ok" => true, "to" => "/my"} = json_response(conn, 200)
    assert {:ok, %{display_name: "Olena", locale: :uk}} = Basa.Accounts.TelegramSignIn.find(777)
  end

  test "after a Mini App sign-in, pages run in Telegram mode until ?telegram=0", %{conn: conn} do
    refute conn |> get(~p"/") |> html_response(200) =~ "telegram-web-app.js"

    data = init_data(%{id: 778, first_name: "Kasia", language_code: "pl"})
    conn = post(conn, ~p"/auth/telegram/webapp", %{init_data: data, to: "/"})
    assert get_session(conn, :telegram_webapp)

    page = conn |> recycle() |> get(~p"/")
    assert html_response(page, 200) =~ "telegram-web-app.js"
    assert html_response(page, 200) =~ ~s(lang="pl")

    off = page |> recycle() |> get(~p"/?telegram=0")
    refute html_response(off, 200) =~ "telegram-web-app.js"
    refute off |> recycle() |> get(~p"/") |> html_response(200) =~ "telegram-web-app.js"
  end

  defp switch_off(services) do
    {:ok, _} =
      Basa.System.update_settings(Basa.System.settings(), %{services_off: services},
        actor: Basa.Fixtures.user(%{role: :admin})
      )
  end

  test "Telegram switched off: no sign-in through it", %{conn: conn} do
    switch_off([:telegram])
    data = init_data(%{id: 779, first_name: "Ivan", language_code: "uk"})
    assert json_response(post(conn, ~p"/auth/telegram/webapp", %{init_data: data}), 401)
    assert {:ok, nil} = Basa.Accounts.TelegramSignIn.find(779)

    conn = get(build_conn(), ~p"/auth/telegram/widget", %{id: "779", hash: "x"})
    assert redirected_to(conn) == ~p"/sign-in"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "switched off"
  end

  test "forged init data is rejected", %{conn: conn} do
    conn =
      post(conn, ~p"/auth/telegram/webapp", %{
        init_data: "user=%7B%22id%22%3A1%7D&auth_date=1&hash=abc"
      })

    assert json_response(conn, 401)
  end

  test "redirect targets stay on BASA", %{conn: conn} do
    data = init_data(%{id: 780, first_name: "Max", language_code: "en"})
    conn = post(conn, ~p"/auth/telegram/webapp", %{init_data: data, to: "//evil.example"})
    assert %{"ok" => true, "to" => "/"} = json_response(conn, 200)
  end
end
