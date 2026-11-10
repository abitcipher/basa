defmodule Basa.Witness.Acts.Countersign do
  use Ash.Resource.Change

  alias Basa.Witness.{Acts, Crypto, Transaction}

  @impl true
  def change(changeset, _opts, context) do
    changeset
    |> Ash.Changeset.before_action(fn changeset ->
      act = changeset.data
      tx = Ash.get!(Transaction, act.transaction_id, authorize?: false)
      signature = Ash.Changeset.get_argument(changeset, :signature)
      party = Acts.party(tx, context.actor.id)

      cond do
        tx.status != :claimed ->
          Ash.Changeset.add_error(changeset, "this settlement is no longer open")

        party && party.role != act.author &&
            Crypto.verify_act(party.public_key, act.hash, signature) ->
          Ash.Changeset.force_change_attributes(changeset, %{
            counter_signature: signature,
            status: :effective,
            effective_at: DateTime.utc_now()
          })

        true ->
          Ash.Changeset.add_error(changeset, "the signature does not match this device's key")
      end
    end)
    |> Ash.Changeset.after_action(fn _changeset, act ->
      Acts.apply_effect(act)
      {:ok, act}
    end)
  end
end
