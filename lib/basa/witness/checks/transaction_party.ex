defmodule Basa.Witness.Checks.TransactionParty do
  use Ash.Policy.SimpleCheck

  require Ash.Query

  @impl true
  def describe(_), do: "actor is a party of the transaction"

  @impl true
  def match?(nil, _context, _opts), do: false

  def match?(actor, %{changeset: %Ash.Changeset{} = changeset}, _opts) do
    case Ash.Changeset.get_argument(changeset, :transaction_id) do
      id when is_binary(id) ->
        Basa.Witness.Party
        |> Ash.Query.filter(transaction_id == ^id and user_id == ^actor.id)
        |> Ash.exists?(authorize?: false)

      _ ->
        false
    end
  end

  def match?(_, _, _), do: false
end
