defmodule Basa.Witness.QES.Start do
  use Ash.Resource.Change

  require Ash.Query

  @impl true
  def change(changeset, _opts, %{actor: actor}) do
    id = Ash.Changeset.get_argument(changeset, :transaction_id)
    provider = Ash.Changeset.get_argument(changeset, :provider)

    party =
      actor && id &&
        Basa.Witness.Party
        |> Ash.Query.filter(transaction_id == ^id and user_id == ^actor.id)
        |> Ash.read_one!(authorize?: false)

    tx = id && Ash.get!(Basa.Witness.Transaction, id, authorize?: false, error?: false)

    cond do
      is_nil(party) ->
        Ash.Changeset.add_error(changeset, field: :transaction_id, message: "not a party")

      is_nil(tx) or is_nil(tx.basa_hash) ->
        Ash.Changeset.add_error(changeset,
          field: :transaction_id,
          message: "only a sealed contract can be signed with a qualified signature"
        )

      is_nil(Basa.Witness.QES.provider(provider)) ->
        Ash.Changeset.add_error(changeset,
          field: :provider,
          message: "this provider is not enabled"
        )

      true ->
        changeset
        |> Ash.Changeset.force_change_attribute(:role, party.role)
        |> Ash.Changeset.force_change_attribute(:user_id, actor.id)
        |> Ash.Changeset.force_change_attribute(:state, :crypto.strong_rand_bytes(16))
    end
  end
end

defmodule Basa.Witness.QES.Complete do
  use Ash.Resource.Change

  require Ash.Query

  alias Basa.Witness.{Party, QES, QualifiedSignature}

  @impl true
  def change(changeset, _opts, _context) do
    record = changeset.data
    cms = Ash.Changeset.get_argument(changeset, :cms)
    tx = Ash.get!(Basa.Witness.Transaction, record.transaction_id, authorize?: false)

    party =
      Party
      |> Ash.Query.filter(transaction_id == ^tx.id and role == ^record.role)
      |> Ash.read_one!(authorize?: false)

    with :ok <- if(record.status == :pending, do: :ok, else: {:error, :already_done}),
         {:ok, v} <- QES.check(cms, tx) do
      {qualification, retry?} = QES.qualification(cms, tx)

      changeset
      |> Ash.Changeset.force_change_attributes(%{
        status: :signed,
        cms: cms,
        subject: v.subject,
        issuer: v.issuer,
        serial: v.serial,
        signing_time: v.signing_time && DateTime.from_unix!(v.signing_time),
        test: v.test?,
        name_matches: QES.name_matches?(v.subject, party),
        signed_at: DateTime.utc_now()
      })
      |> Ash.Changeset.force_change_attributes(qualification)
      |> Ash.Changeset.after_action(fn _cs, result ->
        if retry?, do: Oban.insert!(QES.QualifyWorker.new(%{"id" => result.id}))
        confirm(tx)
        Phoenix.PubSub.broadcast(Basa.PubSub, "witness:#{tx.id}", :witness_changed)
        {:ok, result}
      end)
    else
      {:error, reason} ->
        Ash.Changeset.add_error(changeset,
          field: :cms,
          message: "not accepted: %{reason}",
          vars: [reason: inspect(reason)]
        )
    end
  end

  def signed_pair(tx_id) do
    signed =
      QualifiedSignature
      |> Ash.Query.filter(transaction_id == ^tx_id and status == :signed)
      |> Ash.Query.sort(signed_at: :desc)
      |> Ash.read!(authorize?: false)

    o = Enum.find(signed, &(&1.role == :offeror))
    a = Enum.find(signed, &(&1.role == :acceptor))
    o && a && {o, a}
  end

  def confirm(%{qes_signed_at: nil} = tx) do
    with {o, a} <- signed_pair(tx.id),
         false <- o.test or a.test,
         true <- o.qualification == :qualified and a.qualification == :qualified do
      tx
      |> Ash.Changeset.for_update(:confirm_qualified, %{})
      |> Ash.update!(authorize?: false)
    end
  end

  def confirm(_tx), do: :ok
end

defmodule Basa.Witness.QES.Qualified do
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _cs, record ->
      tx = Ash.get!(Basa.Witness.Transaction, record.transaction_id, authorize?: false)
      Basa.Witness.QES.Complete.confirm(tx)
      Phoenix.PubSub.broadcast(Basa.PubSub, "witness:#{tx.id}", :witness_changed)
      {:ok, record}
    end)
  end
end
