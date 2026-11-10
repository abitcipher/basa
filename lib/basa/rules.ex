defmodule Basa.Rules do
  use Ash.Domain, otp_app: :basa

  resources do
    resource Basa.Rules.RuleSet do
      define :list_rule_sets, action: :read
      define :get_rule_set, action: :read, get_by: [:key]
      define :configure_rule_set, action: :configure
      define :update_rule_graph, action: :update_graph, args: [:graph]
    end

    resource Basa.Rules.RuleSetVersion
  end

  @type review :: :approve | :manual | {:reject, [String.t()]}

  @type photo_review :: :ok | {:flag, [String.t()]} | {:block, [String.t()]}

  @callback review_lot(lot :: struct()) :: review()
  @callback review_photo(scores :: map()) :: photo_review()

  @spec review_lot(struct()) :: review()
  def review_lot(lot), do: engine().review_lot(lot)

  @spec review_photo(map()) :: photo_review()
  def review_photo(scores), do: engine().review_photo(scores)

  defp engine, do: Application.get_env(:basa, :rules_engine, Basa.Rules.Jdm)
end
