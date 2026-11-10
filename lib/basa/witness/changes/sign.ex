defmodule Basa.Witness.Changes.Sign do
  use Ash.Resource.Change

  require Ash.Query

  alias Basa.Witness.{Crypto, Party}

  @impl true
  def change(changeset, _opts, context) do
    changeset
    |> Ash.Changeset.after_action(fn _changeset, tx ->
      if tx.status == :sealed do
        :ok = Basa.Witness.Store.deliver(tx)

        if Basa.Witness.Timestamp.enabled?(),
          do: Oban.insert!(Basa.Witness.TimestampWorker.new(%{transaction_id: tx.id}))
      end

      {:ok, tx}
    end)
    |> Ash.Changeset.before_action(fn changeset ->
      tx = changeset.data
      signature = Ash.Changeset.get_argument(changeset, :signature)

      parties =
        Party |> Ash.Query.filter(transaction_id == ^tx.id) |> Ash.read!(authorize?: false)

      mine = Enum.find(parties, &(&1.user_id == context.actor.id))

      cond do
        is_nil(mine) ->
          Ash.Changeset.add_error(changeset, "only a party can sign")

        mine.signature ->
          Ash.Changeset.add_error(changeset, "already signed")

        not Crypto.verify_seal(mine.public_key, tx.basa_hash, signature) ->
          Ash.Changeset.add_error(changeset, "the signature does not match this device's key")

        true ->
          Ash.update!(mine, %{signature: signature, signed_at: DateTime.utc_now()},
            action: :record_signature,
            authorize?: false
          )

          if Enum.all?(parties, &(&1.id == mine.id or &1.signature)) do
            changeset
            |> Ash.Changeset.force_change_attribute(:status, :sealed)
            |> Ash.Changeset.force_change_attribute(:sealed_at, DateTime.utc_now())
            |> Ash.Changeset.force_change_attribute(
              :deposit_status,
              if(tx.deposit_amount && Decimal.compare(tx.deposit_amount, 0) == :gt,
                do: :held,
                else: :none
              )
            )
          else
            changeset
          end
      end
    end)
  end
end
