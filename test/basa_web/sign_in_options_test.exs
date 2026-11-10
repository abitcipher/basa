defmodule BasaWeb.SignInOptionsTest do
  use BasaWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Basa.Fixtures

  alias Basa.Accounts.{SignInMethods, User}

  setup do
    previous = Application.get_env(:basa, SignInMethods)

    Application.put_env(:basa, SignInMethods,
      google: [client_id: "google-id", client_secret: "google-secret"],
      facebook: [client_id: "fb-id", client_secret: "fb-secret"],
      instagram: []
    )

    on_exit(fn ->
      if previous,
        do: Application.put_env(:basa, SignInMethods, previous),
        else: Application.delete_env(:basa, SignInMethods)
    end)

    :ok
  end

  defp switch_off(methods) do
    Basa.System.settings()
    |> Ash.Changeset.for_update(:update, %{sign_in_off: methods})
    |> Ash.update!(authorize?: false)
  end

  test "the sign-in page offers the options that are set up and switched on", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/sign-in")
    assert has_element?(view, "#user-password-sign-in-with-password")
    assert has_element?(view, "#sign-in-google[href='/auth/user/google']")
    assert has_element?(view, "#sign-in-facebook")
    refute has_element?(view, "#sign-in-instagram")
    refute has_element?(view, "#sign-in-telegram")

    switch_off([:google])
    {:ok, view, _html} = live(conn, ~p"/sign-in")
    refute has_element?(view, "#sign-in-google")
    assert has_element?(view, "#sign-in-facebook")
    assert SignInMethods.available() == [:facebook]
  end

  test "a switched-off or unset option's routes send people back to sign in", %{conn: conn} do
    switch_off([:google])

    for path <- ["/auth/user/google", "/auth/user/google/callback", "/auth/user/instagram"] do
      conn = get(conn, path)
      assert redirected_to(conn) == "/sign-in"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "switched off"
    end

    conn = get(conn, "/auth/user/facebook")
    assert redirected_to(conn) =~ "https://www.facebook.com/v21.0/dialog/oauth"
  end

  test "an admin switches the options on the settings page", %{conn: conn} do
    admin = user(%{role: :admin})
    {:ok, view, _html} = conn |> sign_in(admin) |> live(~p"/admin/settings")

    assert has_element?(view, "#sign-in-instagram-unset")
    assert has_element?(view, "#sign-in-telegram-unset")

    view |> element("#sign-in-google-toggle") |> render_click()
    assert view |> element("#sign-in-google-toggle") |> render() =~ "Off"
    assert SignInMethods.switched_off?(:google)
    refute SignInMethods.on?(:google)

    view |> element("#sign-in-google-toggle") |> render_click()
    assert SignInMethods.on?(:google)
  end

  defp register(method, user_info) do
    strategy = AshAuthentication.Info.strategy!(User, method)

    AshAuthentication.Strategy.action(strategy, :register, %{
      "user_info" => user_info,
      "oauth_tokens" => %{"access_token" => "token", "token_type" => "Bearer"}
    })
  end

  test "Google opens the account with its confirmed email" do
    existing = user(%{email: "olena@example.com"})

    info = %{
      "sub" => "g-1",
      "email" => "olena@example.com",
      "email_verified" => true,
      "name" => "Olena"
    }

    assert {:ok, signed_in} = register(:google, info)
    assert signed_in.id == existing.id

    assert {:ok, again} = register(:google, info)
    assert again.id == existing.id

    assert {:ok, new} =
             register(:google, %{info | "sub" => "g-2", "email" => "max@example.com"})

    assert new.id != existing.id
    assert new.confirmed_at

    assert {:error, _} =
             register(:google, %{
               "sub" => "g-3",
               "email" => "x@example.com",
               "email_verified" => false
             })
  end

  test "Facebook and Instagram find people by their own id, never by email" do
    user(%{email: "olena@example.com"})

    assert {:ok, fb} =
             register(:facebook, %{
               "id" => "fb-1",
               "name" => "Olena",
               "email" => "olena@example.com"
             })

    assert fb.facebook_id == "fb-1"
    assert is_nil(fb.email)
    assert {:ok, fb_again} = register(:facebook, %{"id" => "fb-1", "name" => "Olena"})
    assert fb_again.id == fb.id

    assert {:ok, ig} =
             register(:instagram, %{"id" => 17_841, "user_id" => 99, "username" => "olena.studio"})

    assert ig.instagram_id == "17841"
    assert ig.instagram_username == "olena.studio"
    assert ig.id != fb.id
  end

  test "Telegram sign-in follows its switch", %{conn: conn} do
    previous = Application.get_env(:basa, :telegram)
    Application.put_env(:basa, :telegram, Keyword.put(previous || [], :bot_token, "1:test"))
    on_exit(fn -> Application.put_env(:basa, :telegram, previous) end)

    assert SignInMethods.on?(:telegram)
    switch_off([:telegram])
    refute SignInMethods.on?(:telegram)

    conn = get(conn, "/auth/telegram/widget", %{"id" => "1", "hash" => "x"})
    assert redirected_to(conn) == "/sign-in"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "switched off"
  end
end
