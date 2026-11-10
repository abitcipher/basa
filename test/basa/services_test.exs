defmodule Basa.ServicesTest do
  use BasaWeb.ConnCase, async: true
  use Oban.Testing, repo: Basa.Repo

  import Phoenix.LiveViewTest
  import Basa.Fixtures
  import Swoosh.TestAssertions

  alias Basa.{Services, Witness}
  alias Basa.Witness.{Crypto, Store, Verify}

  defp switch_off(services) do
    {:ok, _} =
      Basa.System.update_settings(Basa.System.settings(), %{services_off: services},
        actor: user(%{role: :admin})
      )

    :ok
  end

  defp reload(tx), do: Witness.get_transaction!(tx.id, authorize?: false)

  defp act(ctx, user, kind, terms, photos \\ []) do
    {:ok, act} = Witness.start_act(ctx.tx.id, kind, %{terms: terms}, actor: user)

    for p <- photos,
        do: {:ok, _} = Store.add(reload(ctx.tx), :photo, "image/jpeg", p, user, act: act)

    {:ok, act} = Witness.fix_act(act, actor: user)
    {:ok, sig} = Crypto.sign_act(ctx.keys[user.id], act.hash)
    Witness.sign_act!(act, sig, actor: user)
  end

  test "every service starts on; admins switch them off and on" do
    for s <- Services.all(), do: refute(Services.switched_off?(s))
    assert Services.on?(:timestamp) and Services.on?(:qes)

    assert {:error, %Ash.Error.Forbidden{}} =
             Basa.System.update_settings(Basa.System.settings(), %{services_off: [:ai]},
               actor: user()
             )

    assert {:error, %Ash.Error.Invalid{}} =
             Basa.System.update_settings(Basa.System.settings(), %{services_off: [:nope]},
               actor: user(%{role: :admin})
             )

    switch_off([:timestamp, :qes])
    refute Services.on?(:timestamp) or Services.on?(:qes)
    assert Services.on?(:mem)
  end

  test "with every service off, a lease runs from booking to closing", %{conn: conn} do
    switch_off(Services.all())

    ctx = Basa.WitnessFixtures.sealed_contract()
    tx = reload(ctx.tx)
    assert tx.status == :sealed
    refute_enqueued(worker: Basa.Witness.TimestampWorker)

    {:ok, view, _} = conn |> sign_in(ctx.lessee) |> live(~p"/transactions/#{tx.id}")
    assert has_element?(view, "#timestamp-off")
    refute has_element?(view, "#mem-confirm")
    refute has_element?(view, "#qes")

    assert {:error, _} = Witness.issue_mem_attestation(tx.id, actor: ctx.lessee)

    returned = act(ctx, ctx.lessee, :return, %{"note" => "all fine"}, ["handed back"])
    assert returned.status == :effective
    act(ctx, ctx.lessor, :acceptance, %{})
    assert reload(tx).status == :closed

    result = Verify.transaction(reload(tx))
    assert result.ok?
    assert {:timestamp, :pending} in result.checks
  end

  test "the timestamp is asked for when the service is back" do
    switch_off([:timestamp])
    ctx = Basa.WitnessFixtures.sealed_contract()
    refute_enqueued(worker: Basa.Witness.TimestampWorker)

    assert {:cancel, :switched_off} =
             perform_job(Basa.Witness.TimestampWorker, %{transaction_id: ctx.tx.id})

    switch_off([])
    assert_enqueued(worker: Basa.Witness.TimestampWorker, args: %{transaction_id: ctx.tx.id})
    :ok = perform_job(Basa.Witness.TimestampWorker, %{transaction_id: ctx.tx.id})
    assert reload(ctx.tx).timestamp_token
  end

  test "qualified signatures off: not offered, stored ones still verify, DSS not asked" do
    assert Witness.QES.providers() != []
    anchors = Witness.QES.anchors()

    switch_off([:qes])
    assert Witness.QES.providers() == []
    assert Witness.QES.anchors() == anchors
    assert Witness.QES.provider(:dev) == nil

    Basa.DssStub.with_dss(:down, fn ->
      assert {:error, :switched_off} = Witness.QES.Dss.validate("cms", "hash")
    end)
  end

  test "email off: no confirmation or reset email is sent" do
    switch_off([:email])
    u = user()

    Basa.Accounts.User
    |> Ash.ActionInput.for_action(:request_password_reset_token, %{email: u.email})
    |> Ash.run_action!(authorize?: false)

    assert_no_email_sent()
  end

  test "OpenStreetMap off: only cities BASA has" do
    switch_off([:osm])
    assert {:error, :disabled} = Basa.Geo.Photon.search("Lviv", "en")
    assert Basa.Geo.external("Lviv") == []
  end

  test "AI off: no suggestions" do
    switch_off([:ai])
    refute Basa.AI.enabled?()
    assert {:error, :disabled} = Basa.AI.recognize("photo", "image/jpeg")
  end

  test "the admin page lists the services and switches them", %{conn: conn} do
    {:ok, view, _} = conn |> sign_in(user(%{role: :admin})) |> live(~p"/admin/settings")

    for s <- Services.all(), do: assert(has_element?(view, "#service-#{s}"))
    assert has_element?(view, "#service-telegram-unset")

    view |> element("#service-timestamp-toggle") |> render_click()
    assert Services.switched_off?(:timestamp)
    assert view |> element("#service-timestamp-toggle") |> render() =~ "Off"

    view |> element("#service-timestamp-toggle") |> render_click()
    refute Services.switched_off?(:timestamp)
  end

  describe "sign-in without Telegram" do
    setup do
      tg =
        Ash.Seed.seed!(Basa.Accounts.User, %{
          telegram_id: System.unique_integer([:positive]),
          display_name: "Olena",
          locale: :en
        })

      %{tg: tg}
    end

    test "a Telegram user adds an email and a password, once", %{conn: conn, tg: tg} do
      {:ok, view, _} = conn |> sign_in(tg) |> live(~p"/profile")
      assert has_element?(view, "#password-sign-in")

      view
      |> form("#password-sign-in-form",
        sign_in: %{
          email: "olena@example.com",
          password: "secret12",
          password_confirmation: "nope"
        }
      )
      |> render_submit()

      assert has_element?(view, "#password-sign-in-error")

      view
      |> form("#password-sign-in-form",
        sign_in: %{
          email: "olena@example.com",
          password: "secret12",
          password_confirmation: "secret12"
        }
      )
      |> render_submit()

      refute has_element?(view, "#password-sign-in")

      assert {:ok, [signed_in]} =
               Basa.Accounts.User
               |> Ash.Query.for_read(:sign_in_with_password, %{
                 email: "olena@example.com",
                 password: "secret12"
               })
               |> Ash.read(authorize?: false)

      assert signed_in.id == tg.id

      tg = Ash.get!(Basa.Accounts.User, tg.id, authorize?: false)

      assert {:error, _} =
               Basa.Accounts.add_password_sign_in(
                 tg,
                 %{
                   email: "other@example.com",
                   password: "another12",
                   password_confirmation: "another12"
                 },
                 actor: tg
               )
    end

    test "someone with a password doesn't see the form", %{conn: conn} do
      {:ok, view, _} = conn |> sign_in(user()) |> live(~p"/profile")
      refute has_element?(view, "#password-sign-in")
    end
  end
end
