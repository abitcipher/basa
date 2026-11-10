defmodule Basa.Rules.Check do
  alias Basa.Rules.{Library, RuleSet}
  alias RulesEngine, as: Engine

  @type violation :: %{rule: map(), code: String.t() | nil, message: String.t() | nil}

  @spec run(String.t(), String.t(), map()) :: [violation()]
  def run(point, subject, context) do
    point
    |> rule_sets(subject)
    |> Enum.flat_map(&evaluate_rule(&1, context))
  end

  def any?(violations, severity), do: Enum.any?(violations, &(&1.rule.severity == severity))

  defp rule_sets(point, subject) do
    stored = Ash.read!(RuleSet, authorize?: false)

    rules =
      if stored == [] do
        Enum.map(Library.files(), fn f ->
          %{
            key: f["key"],
            severity: String.to_existing_atom(f["severity"]),
            enabled: true,
            points: f["points"],
            subjects: f["subjects"],
            graph: f["graph"],
            version: f["version"] || 1
          }
        end)
      else
        stored
      end

    Enum.filter(rules, &(&1.enabled and point in &1.points and subject in &1.subjects))
  end

  defp evaluate_rule(rule, context) do
    case Engine.evaluate(rule.graph, context) do
      {:ok, %{"valid" => true}} -> []
      {:ok, result} -> [%{rule: rule, code: result["code"], message: result["message"]}]
      {:error, reason} -> [%{rule: rule, code: "rule_error", message: inspect(reason)}]
    end
  end
end
