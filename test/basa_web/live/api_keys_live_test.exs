defmodule BasaWeb.ApiKeysLiveTest do
  use BasaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Basa.Fixtures

  test "a key is made, shown once, works on the API, and is revoked", %{conn: conn} do
    owner = user()
    {:ok, view, _} = conn |> sign_in(owner) |> live(~p"/profile")

    view |> form("#api-key-form", key: %{name: "Shop sync", days: "30"}) |> render_submit()

    secret =
      view
      |> element("#new-api-key-text")
      |> render()
      |> Floki.parse_fragment!()
      |> Floki.text()
      |> String.trim()

    assert "basa_" <> _ = secret

    [key] = Basa.Accounts.list_api_keys!(actor: owner)
    assert key.name == "Shop sync"
    assert DateTime.diff(key.expires_at, DateTime.utc_now(), :day) in 29..30
    assert has_element?(view, "#api-key-#{key.id}", "not used yet")

    api =
      build_conn()
      |> put_req_header("accept", "application/vnd.api+json")
      |> put_req_header("authorization", "Bearer " <> secret)

    assert api |> get("/api/json/items") |> json_response(200)
    view |> element("button", "I saved it") |> render_click()
    refute has_element?(view, "#new-api-key")

    view |> element("#api-key-#{key.id} button", "Revoke") |> render_click()
    refute has_element?(view, "#api-key-#{key.id}")

    assert build_conn()
           |> put_req_header("accept", "application/vnd.api+json")
           |> put_req_header("authorization", "Bearer " <> secret)
           |> get("/api/json/items")
           |> json_response(401)
  end

  test "someone else's keys are not listed", %{conn: conn} do
    other = user()

    {:ok, _} =
      Basa.Accounts.create_api_key("Theirs", DateTime.add(DateTime.utc_now(), 1, :day),
        actor: other
      )

    {:ok, view, _} = conn |> sign_in(user()) |> live(~p"/profile")
    refute render(view) =~ "Theirs"
  end
end
