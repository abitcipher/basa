defmodule Basa.Witness.QESLevel4Test do
  use BasaWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Basa.WitnessFixtures

  require Ash.Query

  alias Basa.{DssStub, TrustedQESProvider}
  alias Basa.Witness
  alias Basa.Witness.{Disclosure, Party, Verify}

  test "two signatures from a trusted provider, qualified by the EU DSS, reach level 4" do
    DssStub.with_dss(DssStub.qualified(), fn -> level4() end)
  end

  defp level4 do
    TrustedQESProvider.with_trusted(fn ->
      ctx = sealed_contract()

      for user <- [ctx.lessor, ctx.lessee] do
        party =
          Party
          |> Ash.Query.filter(transaction_id == ^ctx.tx.id and user_id == ^user.id)
          |> Ash.read_one!(authorize?: false)

        {:ok, record} = Witness.start_qualified_signature(ctx.tx.id, :trusted, actor: user)
        {:ok, cms} = TrustedQESProvider.sign(user.id, party.legal_name, ctx.tx.basa_hash)
        {:ok, signed} = Witness.complete_qualified_signature(record, cms, actor: user)
        refute signed.test
        assert signed.qualification == :qualified
        assert signed.qualification_level == "QESig"
      end

      tx = Ash.reload!(ctx.tx, authorize?: false)
      assert tx.qes_signed_at
      assert {{:qualified, :acceptor}, :ok} in Verify.transaction(tx).checks

      {:ok, pkg} = Disclosure.build(tx, [0])
      assert {{:qualified, "offeror"}, :ok} in Disclosure.check(pkg).checks

      {:ok, view, _} = live(build_conn() |> sign_in(ctx.lessor), ~p"/transactions/#{tx.id}")
      assert has_element?(view, "#qes-done")
      assert has_element?(view, "#qes-offeror-qualified")
      refute render(view) =~ "test signature, not qualified"
    end)
  end
end
