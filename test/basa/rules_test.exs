defmodule Basa.RulesTest do
  use Basa.DataCase, async: true

  import Basa.Fixtures
  alias Basa.Rules
  alias Basa.Rules.Library
  alias RulesEngine, as: Engine

  @title_rule "priv/rules/lot_title_length.json" |> File.read!() |> Jason.decode!()

  describe "engine (NIF)" do
    test "evaluates a JDM graph" do
      assert {:ok, %{"valid" => true}} =
               Engine.evaluate(@title_rule["graph"], %{"lot" => %{"titleLength" => 12}})

      assert {:ok, %{"valid" => false, "code" => "lot_title_short"}} =
               Engine.evaluate(@title_rule["graph"], %{"lot" => %{"titleLength" => 2}})
    end

    test "a trace shows each node; broken graphs are reported, not raised" do
      {:ok, result} =
        Engine.evaluate(@title_rule["graph"], %{"lot" => %{"titleLength" => 2}}, trace: true)

      assert is_map(result["trace"])

      assert :ok = Engine.validate(@title_rule["graph"])
      assert {:error, _} = Engine.validate(%{"nodes" => [], "edges" => []})
      assert {:error, _} = Engine.evaluate(%{"nodes" => "nope"}, %{})
    end

    test "every shipped rule is a valid graph" do
      for file <- Library.files(), do: assert(:ok = Engine.validate(file["graph"]), file["key"])
    end
  end

  describe "library and editing" do
    test "sync adds shipped rules once" do
      assert Library.sync() == length(Library.files())
      assert Library.sync() == 0
    end

    test "an admin's graph edit is validated and the old graph is kept as a version" do
      Library.sync()
      admin = user(%{role: :admin})
      rule = Rules.get_rule_set!("lot_title_length", actor: admin)

      assert {:error, _} = Rules.update_rule_graph(rule, %{"nodes" => []}, actor: admin)

      assert {:error, %Ash.Error.Forbidden{}} =
               Rules.update_rule_graph(rule, rule.graph, actor: user())

      stricter =
        put_in(
          rule.graph,
          ["nodes", Access.at(1), "content", "expressions", Access.at(0), "value"],
          "lot.titleLength >= 10"
        )

      {:ok, updated} = Rules.update_rule_graph(rule, stricter, actor: admin)
      assert updated.version == 2
      assert updated.updated_by_email == to_string(admin.email)

      assert [%{version: 1}] = Ash.read!(Basa.Rules.RuleSetVersion, actor: admin)

      assert Library.sync() == 0
    end

    test "disabling a rule takes it out of the review", ctx do
      _ = ctx
      Library.sync()
      admin = user(%{role: :admin})
      rule = Rules.get_rule_set!("lot_title_length", actor: admin)
      Rules.configure_rule_set!(rule, %{enabled: false}, actor: admin)

      lessor = user()
      lot = lot(lessor, basket(lessor, [item(lessor)]), room(lessor), %{title: "Hi"})
      assert Basa.Catalog.submit_lot!(lot, actor: lessor).state == :published
    end
  end

  describe "review decisions" do
    setup do
      lessor = user()
      %{lessor: lessor, room: room(lessor), basket: basket(lessor, [item(lessor)])}
    end

    defp review(ctx, attrs, items \\ nil) do
      basket = if items, do: basket(ctx.lessor, items), else: ctx.basket
      lot = lot(ctx.lessor, basket, ctx.room, attrs)
      lot = Ash.load!(lot, [:room, basket: [:items, :attendants]], authorize?: false)
      {Basa.Rules.Jdm.review_lot(lot), Basa.Rules.Builtin.review_lot(lot)}
    end

    test "JDM rules and the Elixir fallback agree", ctx do
      assert {:approve, :approve} = review(ctx, %{})

      {{:reject, jdm}, {:reject, builtin}} = review(ctx, %{title: "Hi", price_amount: 0})
      assert Enum.sort(jdm) == Enum.sort(builtin)

      expensive = [item(ctx.lessor, %{estimated_value: 9_000_000})]
      assert {:manual, :manual} = review(ctx, %{}, expensive)
    end

    test "reasons come in the lessor's language", ctx do
      Gettext.with_locale(BasaWeb.Gettext, "uk", fn ->
        {{:reject, reasons}, _} = review(ctx, %{title: "Hi"})
        assert "Назва закоротка" in reasons
      end)
    end
  end
end
