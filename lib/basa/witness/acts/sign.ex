defmodule Basa.Witness.Acts.Sign do
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

      if party && Crypto.verify_act(party.public_key, act.hash, signature) do
        if act.kind == :settlement do
          Ash.Changeset.force_change_attributes(changeset, %{
            author_signature: signature,
            status: :awaiting_counter
          })
        else
          Ash.Changeset.force_change_attributes(changeset, %{
            author_signature: signature,
            status: :effective,
            effective_at: DateTime.utc_now()
          })
        end
      else
        Ash.Changeset.add_error(changeset, "the signature does not match this device's key")
      end
    end)
    |> Ash.Changeset.after_action(fn _changeset, act ->
      if act.status == :effective, do: Acts.apply_effect(act)
      {:ok, act}
    end)
  end
end
