defmodule Basa.ModerationTest do
  use BasaWeb.ConnCase, async: true
  use Oban.Testing, repo: Basa.Repo

  import Phoenix.LiveViewTest
  import Basa.Fixtures

  require Ash.Query

  alias Basa.Moderation
  alias Basa.Moderation.{CheckWorker, PhotoCheck}

  @jpeg <<0xFF, 0xD8, 0xFF, 0xE0>> <> :binary.copy(<<1>>, 32)

  defp stored(owner, folder \\ "items") do
    {:ok, key} = Basa.Storage.store("#{folder}/#{owner.id}", @jpeg, "image/jpeg")
    key
  end

  defp check_of(key),
    do:
      PhotoCheck
      |> Ash.Query.filter(key == ^key)
      |> Ash.Query.load(:hidden?)
      |> Ash.read_one!(authorize?: false)

  defp checked(key, scores \\ %{}) do
    Basa.ModerationStub.scores(scores)
    assert :ok = perform_job(CheckWorker, %{key: key})
    check_of(key)
  end

  defp switch_off(services) do
    {:ok, _} =
      Basa.System.update_settings(Basa.System.settings(), %{services_off: services},
        actor: user(%{role: :admin})
      )
  end

  test "a stored photo waits for its check, with its owner" do
    owner = user()
    key = stored(owner)
    assert %{status: :pending, owner_id: owner_id} = check_of(key)
    assert owner_id == owner.id
    assert_enqueued(worker: CheckWorker, args: %{key: key})

    {:ok, pdf} = Basa.Storage.store("items/#{owner.id}", "%PDF", "application/pdf")
    refute check_of(pdf)
  end

  test "a plain photo passes; scores and models are kept" do
    key = stored(user())
    check = checked(key)
    assert %{status: :checked, verdict: :ok, reasons: [], level: 1} = check
    assert check.scores["nsfw"] == 0.02 and check.models != []
    refute check.hidden?
  end

  test "clear nudity is hidden: only its owner and admins see it" do
    owner = user()
    key = stored(owner)

    assert %{verdict: :block, reasons: ["photo_nudity_clear"], hidden?: true} =
             checked(key, %{"nsfw" => 0.97})

    assert build_conn() |> get("/media/#{key}") |> response(404)
    assert build_conn() |> sign_in(user()) |> get("/media/#{key}") |> response(404)

    for viewer <- [owner, user(%{role: :admin})] do
      conn = build_conn() |> sign_in(viewer) |> get("/media/#{key}")
      assert response(conn, 200)
      assert get_resp_header(conn, "cache-control") == ["private, no-store"]
    end

    {:ok, _view, html} = build_conn() |> sign_in(owner) |> live(~p"/my")
    assert html =~ "hidden-photos"
    assert html =~ "nudity"
  end

  test "possible nudity, weapons and documents go to an admin, who keeps or removes" do
    owner = user()
    admin = user(%{role: :admin})
    nude = stored(owner)
    gun = stored(owner, "rooms")
    passport = stored(owner, "entrance")

    assert %{verdict: :flag, reasons: ["photo_nudity_possible"], hidden?: false} =
             checked(nude, %{"nsfw" => 0.7})

    assert %{verdict: :flag, reasons: ["photo_harm"]} =
             checked(gun, %{"clip" => %{"weapon" => 0.8}})

    assert %{verdict: :flag, reasons: ["photo_documents"]} =
             checked(passport, %{"clip" => %{"document" => 0.7}})

    assert build_conn() |> get("/media/#{gun}") |> response(200)

    {:ok, view, _} = build_conn() |> sign_in(admin) |> live(~p"/admin/photos")

    for key <- [nude, gun, passport],
        do: assert(has_element?(view, "#photo-check-#{check_of(key).id}"))

    view |> element("#remove-#{check_of(gun).id}") |> render_click()
    view |> element("#keep-#{check_of(nude).id}") |> render_click()
    refute has_element?(view, "#photo-check-#{check_of(gun).id}")

    assert %{review: :removed, hidden?: true, updated_by_email: email} = check_of(gun)
    assert email == to_string(admin.email)
    assert build_conn() |> get("/media/#{gun}") |> response(404)

    assert %{review: :removed, hidden?: true} = checked(gun, %{"clip" => %{"weapon" => 0.1}})
    assert %{review: :kept, hidden?: false} = checked(nude, %{"nsfw" => 0.95})
  end

  test "an offer with a hidden photo goes back to draft, until an admin keeps it" do
    owner = user()
    item = item(owner)
    key = stored(owner)
    item = Basa.Catalog.update_item!(item, %{photos: [key]}, actor: owner)
    checked(key, %{"nsfw" => 0.99})

    lot = lot(owner, basket(owner, [item]), room(owner))
    lot = Basa.Catalog.submit_lot!(lot, actor: owner)
    assert lot.state == :draft
    assert lot.review_note =~ "hidden after a check"

    {:ok, _} = Moderation.review_photo(check_of(key), :kept, actor: user(%{role: :admin}))
    assert Basa.Catalog.submit_lot!(lot, actor: owner).state == :published
  end

  test "the JDM rules and the Elixir fallback judge photos alike" do
    for scores <- [
          %{},
          %{"nsfw" => 0.95},
          %{"nsfw" => 0.65},
          %{"nsfw" => 0.89, "clip" => %{"weapon" => 0.6}},
          %{"clip" => %{"drugs" => 0.7, "document" => 0.6}},
          %{"clip" => %{"gore" => 0.49}},
          %{"nsfw" => 0.95, "clip" => %{"document" => 0.9}}
        ] do
      scores = Map.merge(%{"nsfw" => 0.01, "level" => 1, "clip" => %{}}, scores)

      assert Basa.Rules.Jdm.review_photo(scores) == Basa.Rules.Builtin.review_photo(scores),
             inspect(scores)
    end
  end

  test "switched off: photos wait; switched on again: they are queued" do
    switch_off([:moderation])
    key = stored(user())
    refute_enqueued(worker: CheckWorker)
    assert :ok = perform_job(CheckWorker, %{key: key})
    assert check_of(key).status == :pending

    switch_off([])
    assert_enqueued(worker: CheckWorker, args: %{key: key})
  end

  test "while the checker loads a level, the check waits and tries again" do
    key = stored(user())
    Process.put({Basa.ModerationStub, :error}, {:error, :not_ready})
    assert {:snooze, _} = perform_job(CheckWorker, %{key: key})
    assert check_of(key).status == :pending
  end

  test "checking everything again also covers photos stored before checks existed" do
    owner = user()
    old = "items/#{owner.id}/from-before.jpg"
    :ok = Basa.Storage.put(old, @jpeg, "image/jpeg")
    Basa.Catalog.update_item!(item(owner), %{photos: [old]}, actor: owner)
    refute check_of(old)

    assert Moderation.recheck_all() >= 1
    assert %{status: :pending, owner_id: owner_id} = check_of(old)
    assert owner_id == owner.id
    assert_enqueued(worker: CheckWorker, args: %{key: old})
  end

  test "way-in photos and street views are served like other photos" do
    owner = user()

    for folder <- ~w(entrance street) do
      key = stored(owner, folder)
      checked(key)
      conn = build_conn() |> get("/media/#{key}")
      assert response(conn, 200)
      assert get_resp_header(conn, "cache-control") == ["public, max-age=31536000, immutable"]
    end
  end

  test "settings: the level, the counts and checking everything again", %{conn: conn} do
    admin = user(%{role: :admin})
    stored(user())
    {:ok, view, _} = conn |> sign_in(admin) |> live(~p"/admin/settings")

    assert has_element?(view, "#moderation-status", "level 1")
    assert has_element?(view, "#moderation-counts", "1")

    view |> form("#moderation-level-form", %{level: "2"}) |> render_change()
    assert Basa.System.settings().moderation_level == 2

    view |> element("#moderation-recheck") |> render_click()
    assert render(view) =~ "will be checked again"
  end
end
