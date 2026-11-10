defmodule Basa.Rules.Library do
  alias Basa.Rules.RuleSet

  @spec files() :: [map()]
  def files do
    Application.app_dir(:basa, "priv/rules")
    |> Path.join("*.json")
    |> Path.wildcard()
    |> Enum.sort()
    |> Enum.map(&(&1 |> File.read!() |> Jason.decode!()))
  end

  @spec sync() :: non_neg_integer()
  def sync do
    existing = RuleSet |> Ash.read!(authorize?: false) |> Map.new(&{&1.key, &1})
    files = files()

    added =
      files |> Enum.reject(&Map.has_key?(existing, &1["key"])) |> Enum.map(&seed/1) |> length()

    upgraded =
      files
      |> Enum.filter(&upgradable?(existing[&1["key"]], &1))
      |> Enum.map(&upgrade(existing[&1["key"]], &1))
      |> length()

    added + upgraded
  end

  defp upgradable?(nil, _file), do: false

  defp upgradable?(rule, file),
    do: is_nil(rule.updated_by_email) and (file["version"] || 1) > rule.version

  defp upgrade(rule, file) do
    Basa.Rules.RuleSetVersion
    |> Ash.Changeset.for_create(
      :create,
      %{key: rule.key, version: rule.version, graph: rule.graph, replaced_by_email: nil},
      authorize?: false
    )
    |> Ash.create!(authorize?: false)

    rule
    |> Ash.Changeset.for_update(
      :ship,
      Map.take(atomize(file), [:label, :description, :points, :subjects, :graph, :version]),
      authorize?: false
    )
    |> Ash.update!(authorize?: false)
  end

  defp seed(file) do
    attrs =
      file
      |> atomize()
      |> Map.take([:key, :label, :description, :points, :subjects, :graph])
      |> Map.merge(%{
        severity: String.to_existing_atom(file["severity"]),
        version: file["version"] || 1
      })

    RuleSet
    |> Ash.Changeset.for_create(:seed, attrs, authorize?: false)
    |> Ash.create!(authorize?: false)
  end

  defp atomize(file), do: Map.new(file, fn {k, v} -> {String.to_atom(k), v} end)
end
