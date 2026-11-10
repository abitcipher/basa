defmodule Basa.Witness.Acts.AutoAccept do
  use Ash.Resource.Change

  alias Basa.Witness.{Acts, Transaction}

  @impl true
  def change(changeset, _opts, _context) do
    changeset
    |> Ash.Changeset.force_change_attributes(%{kind: :auto_acceptance, author: :basa})
    |> Ash.Changeset.before_action(fn changeset ->
      tx =
        Ash.get!(Transaction, Ash.Changeset.get_argument(changeset, :transaction_id),
          authorize?: false
        )

      now = DateTime.utc_now()
      {previous, sequence} = Acts.tail(tx)

      with :ok <- Acts.allowed?(tx, :auto_acceptance, :basa, now),
           {:ok, bytes, hash} <- Acts.encode(tx, :auto_acceptance, :basa, %{}, [], previous, now) do
        Ash.Changeset.force_change_attributes(changeset, %{
          bytes: bytes,
          hash: hash,
          previous: previous,
          sequence: sequence,
          status: :effective,
          effective_at: now
        })
      else
        {:error, message} -> Ash.Changeset.add_error(changeset, message)
      end
    end)
    |> Ash.Changeset.after_action(fn _changeset, act ->
      Acts.apply_effect(act)
      {:ok, act}
    end)
  end
end
