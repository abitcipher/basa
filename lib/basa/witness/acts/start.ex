defmodule Basa.Witness.Acts.Start do
  use Ash.Resource.Change

  alias Basa.Witness.{Acts, Transaction}

  @impl true
  def change(changeset, _opts, context) do
    tx =
      Ash.get!(Transaction, Ash.Changeset.get_argument(changeset, :transaction_id),
        authorize?: false
      )

    kind = Ash.Changeset.get_attribute(changeset, :kind)
    party = Acts.party(tx, context.actor.id)

    case party && Acts.allowed?(tx, kind, party.role) do
      :ok ->
        changeset
        |> Ash.Changeset.force_change_attribute(:author, party.role)
        |> Ash.Changeset.force_change_attribute(:author_user_id, context.actor.id)
        |> Ash.Changeset.after_action(fn _changeset, act ->
          Basa.Witness.Store.new_act_key(act)
        end)

      {:error, message} ->
        Ash.Changeset.add_error(changeset, message)

      nil ->
        Ash.Changeset.add_error(changeset, "only a party can do this")
    end
  end
end
