defmodule Basa.Witness.Validations.TransactionStatus do
  use Ash.Resource.Validation

  @impl true
  def init(opts), do: {:ok, opts}

  @impl true
  def validate(changeset, opts, _context) do
    tx = Ash.get!(Basa.Witness.Transaction, changeset.data.transaction_id, authorize?: false)

    if tx.status in opts[:statuses],
      do: :ok,
      else: {:error, message: "the contract can no longer be changed"}
  end
end
