defmodule Basa.Witness.QESTest do
  use BasaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Basa.WitnessFixtures

  require Ash.Query

  alias Basa.Witness
  alias Basa.Witness.{Disclosure, Native, Party, QES, Verify}
  alias Basa.Witness.QES.DevProvider

  setup do
    ctx = sealed_contract()

    names =
      Party
      |> Ash.Query.filter(transaction_id == ^ctx.tx.id)
      |> Ash.read!(authorize?: false)
      |> Map.new(&{&1.user_id, &1.legal_name})

    %{ctx: ctx, names: names}
  end

  defp sign(ctx, names, user) do
    {:ok, record} = Witness.start_qualified_signature(ctx.tx.id, :dev, actor: user)
    {:ok, cms} = DevProvider.sign(user.id, names[user.id], ctx.tx.basa_hash)
    {record, cms}
  end

  test "both parties sign with the test CA: valid, but not level 4", %{
    ctx: ctx,
    names: names
  } do
    {record, cms} = sign(ctx, names, ctx.lessor)
    assert record.role == :offeror
    {:ok, signed} = Witness.complete_qualified_signature(record, cms, actor: ctx.lessor)
    assert signed.status == :signed
    assert signed.test
    assert signed.name_matches
    assert signed.subject == names[ctx.lessor.id]
    assert signed.issuer == "BASA test CA (not qualified)"
    refute Ash.reload!(ctx.tx, authorize?: false).qes_signed_at

    {record, cms} = sign(ctx, names, ctx.lessee)
    {:ok, _} = Witness.complete_qualified_signature(record, cms, actor: ctx.lessee)
    tx = Ash.reload!(ctx.tx, authorize?: false)
    refute tx.qes_signed_at

    {:ok, view, _} = live(build_conn() |> sign_in(ctx.lessee), ~p"/transactions/#{ctx.tx.id}")
    assert has_element?(view, "#qes-test-only")
    refute has_element?(view, "#qes-done")

    checks = Verify.transaction(tx).checks
    assert {{:qualified, :offeror}, :test} in checks
    assert Verify.transaction(tx).ok?
    {:ok, pkg} = Disclosure.build(tx, [0])
    assert length(pkg["qualified_signatures"]) == 2
    result = pkg |> Jason.encode!() |> Disclosure.check_json()
    assert result.ok?
    assert {{:qualified, "acceptor"}, :test} in result.checks

    other = sealed_contract()
    {:ok, foreign} = DevProvider.sign(ctx.lessor.id, "X", other.tx.basa_hash)

    forged =
      put_in(pkg, ["qualified_signatures", Access.at(0), "cms"], Base.encode64(foreign))

    assert {{:qualified, "offeror"}, {:error, :mismatch}} in Disclosure.check(forged).checks
    refute Disclosure.check(forged).ok?
  end

  test "signatures of another document or from an unknown CA are refused", %{
    ctx: ctx,
    names: names
  } do
    {record, _} = sign(ctx, names, ctx.lessor)

    {:ok, wrong_doc} = DevProvider.sign(ctx.lessor.id, "Olena", :binary.copy(<<1>>, 32))

    assert {:error, _} =
             Witness.complete_qualified_signature(record, wrong_doc, actor: ctx.lessor)

    {:ok, other_ca} =
      Native.qes_dev_sign("another seed", ctx.lessor.id, "Olena", ctx.tx.basa_hash)

    assert {:error, :unknown_issuer} = QES.check(other_ca, ctx.tx)
    assert {:error, _} = Witness.complete_qualified_signature(record, other_ca, actor: ctx.lessor)

    assert {:error, _} =
             Witness.complete_qualified_signature(record, "garbage", actor: ctx.lessor)

    {:ok, cms} = DevProvider.sign(ctx.lessor.id, "Olena", ctx.tx.basa_hash)
    assert {:error, _} = Witness.complete_qualified_signature(record, cms, actor: ctx.lessee)
  end

  test "a name that differs from the legal name is flagged", %{ctx: ctx, names: names} do
    {record, _} = sign(ctx, names, ctx.lessor)
    {:ok, cms} = DevProvider.sign(ctx.lessor.id, "Somebody Else", ctx.tx.basa_hash)
    {:ok, signed} = Witness.complete_qualified_signature(record, cms, actor: ctx.lessor)
    refute signed.name_matches
  end

  test "only parties, only enabled providers", %{ctx: ctx} do
    assert {:error, _} =
             Witness.start_qualified_signature(ctx.tx.id, :dev, actor: Basa.Fixtures.user())

    assert {:error, _} = Witness.start_qualified_signature(ctx.tx.id, :diia, actor: ctx.lessor)
  end

  describe "the provider's return" do
    test "signs in the signer's session and shows it on the page", %{ctx: ctx, names: names} do
      conn = build_conn() |> sign_in(ctx.lessor)
      {:ok, view, _} = live(conn, ~p"/transactions/#{ctx.tx.id}")
      assert has_element?(view, "#qes-offeror", "not yet")

      assert {:error, {:redirect, %{to: "/dev/qes/" <> token}}} =
               view |> element("#qes-start-dev") |> render_click()

      {:ok, state} = QES.state_from_token(token)

      record =
        Basa.Witness.QualifiedSignature
        |> Ash.Query.filter(state == ^state)
        |> Ash.read_one!(authorize?: false)

      {:ok, cms} = DevProvider.sign(ctx.lessor.id, names[ctx.lessor.id], ctx.tx.basa_hash)
      path = URI.parse(DevProvider.return_with(record, cms))

      other = build_conn() |> sign_in(ctx.lessee) |> get(path.path <> "?" <> path.query)
      assert redirected_to(other) == ~p"/bookings"

      back = build_conn() |> sign_in(ctx.lessor) |> get(path.path <> "?" <> path.query)
      assert redirected_to(back) == ~p"/transactions/#{ctx.tx.id}"
      assert Phoenix.Flash.get(back.assigns.flash, :info) =~ "qualified signature was added"

      {:ok, view, _} = live(build_conn() |> sign_in(ctx.lessor), ~p"/transactions/#{ctx.tx.id}")
      assert has_element?(view, "#qes-offeror", names[ctx.lessor.id])
      assert render(view) =~ "test signature, not qualified"
      refute has_element?(view, "#qes-start-dev")
    end

    test "a cancelled signing says so and can be tried again", %{ctx: ctx} do
      {:ok, record} = Witness.start_qualified_signature(ctx.tx.id, :dev, actor: ctx.lessor)
      path = URI.parse(QES.return_url(record) <> "?error=cancelled")
      conn = build_conn() |> sign_in(ctx.lessor) |> get(path.path <> "?" <> path.query)
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "cancelled"
      assert Ash.reload!(record, authorize?: false).status == :failed
    end
  end
end
