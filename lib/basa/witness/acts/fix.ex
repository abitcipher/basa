defmodule Basa.Witness.Acts.Fix do
  use Ash.Resource.Change

  alias Basa.Witness.{Acts, Transaction}

  @impl true
  def change(changeset, _opts, _context) do
    changeset
    |> Ash.Changeset.before_action(fn changeset ->
      act = changeset.data
      tx = Ash.get!(Transaction, act.transaction_id, authorize?: false)
      files = Acts.files(act.id)
      {previous, sequence} = Acts.tail(tx)

      with :ok <- Acts.allowed?(tx, act.kind, act.author),
           :ok <- Acts.check_content(act.kind, act.terms, files, tx),
           {:ok, bytes, hash} <-
             Acts.encode(tx, act.kind, act.author, act.terms, files, previous, DateTime.utc_now()) do
        changeset
        |> Ash.Changeset.force_change_attributes(%{
          bytes: bytes,
          hash: hash,
          previous: previous,
          sequence: sequence,
          status: :unsigned
        })
      else
        {:error, message} -> Ash.Changeset.add_error(changeset, message)
      end
    end)
    |> Ash.Changeset.after_action(fn _changeset, act ->
      tx = Ash.get!(Transaction, act.transaction_id, authorize?: false)
      :ok = Basa.Witness.Store.deliver(tx, act: act)
      {:ok, act}
    end)
  end
end
