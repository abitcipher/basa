defmodule Basa.Witness.Verify do
  require Ash.Query

  alias Basa.Witness.{AccessLog, Crypto, Evidence, Party, Store, Transaction}

  @probe "BASA witness key check"

  def transaction(%Transaction{} = tx, opts \\ []) do
    evidence =
      Evidence
      |> Ash.Query.filter(transaction_id == ^tx.id and is_nil(act_id))
      |> Ash.Query.sort(position: :asc)
      |> Ash.read!(authorize?: false)

    parties = Party |> Ash.Query.filter(transaction_id == ^tx.id) |> Ash.read!(authorize?: false)

    checks =
      [{:keys, keys(tx)}] ++
        files(tx, evidence) ++
        sealed(tx, evidence, parties) ++
        in_person(tx) ++
        qualified(tx) ++
        acts(tx, parties)

    ok? =
      Enum.all?(checks, fn {_, result} -> result in [:ok, :pending, :test, :not_qualified] end)

    log(tx, ok?, checks, opts)
    %{ok?: ok?, checks: checks}
  end

  def all(opts \\ []) do
    Transaction
    |> Ash.Query.sort(inserted_at: :asc)
    |> Ash.read!(authorize?: false)
    |> Enum.map(&{&1.id, transaction(&1, opts)})
  end

  defp keys(tx) do
    rows =
      Basa.Witness.KeyShare
      |> Ash.Query.filter(transaction_id == ^tx.id and is_nil(act_id))
      |> Ash.read!(authorize?: false)

    readable = for r <- rows, r.share, do: r.owner

    cond do
      Enum.sort(readable) == [:acceptor, :basa, :offeror] ->
        with {:ok, key} <- Store.key(tx), do: Store.check(key, @probe, tx)

      :basa not in readable ->
        {:error, :basa_share_missing}

      not Enum.all?(rows, &(&1.owner == :basa or &1.sealed_share)) ->
        {:error, :party_share_missing}

      is_nil(tx.recovery_sealed) ->
        {:error, :recovery_seal_missing}

      true ->
        :ok
    end
  end

  defp files(tx, evidence) do
    positions =
      if Enum.map(evidence, & &1.position) == Enum.to_list(0..(length(evidence) - 1)//1),
        do: :ok,
        else: {:error, :positions_not_contiguous}

    [{:positions, positions}] ++
      for e <- evidence do
        {{:file, e.position}, Store.intact(e, tx)}
      end
  end

  defp sealed(%Transaction{manifest: nil}, _evidence, _parties), do: []

  defp sealed(tx, evidence, parties) do
    case Crypto.decode_manifest(tx.manifest) do
      {:error, reason} ->
        [{:manifest, {:error, reason}}]

      {:ok, m} ->
        hash = Crypto.basa_hash(tx.manifest)

        [
          {:manifest, manifest_matches(m, tx, evidence, parties)},
          {:basa_hash, if(hash == tx.basa_hash, do: :ok, else: {:error, :mismatch})}
        ] ++
          timestamp(tx) ++
          for p <- Enum.sort_by(parties, & &1.role),
              not (is_nil(p.signature) and tx.status == :signing) do
            result =
              cond do
                is_nil(p.signature) -> {:error, :not_signed}
                Crypto.verify_seal(p.public_key, hash, p.signature) -> :ok
                true -> {:error, :bad_signature}
              end

            {{:signature, p.role}, result}
          end
    end
  end

  defp qualified(%Transaction{basa_hash: nil}), do: []

  defp qualified(tx) do
    Basa.Witness.QualifiedSignature
    |> Ash.Query.filter(transaction_id == ^tx.id and status == :signed)
    |> Ash.read!(authorize?: false)
    |> Enum.map(&{{:qualified, &1.role}, qualified_result(&1, tx)})
  end

  defp qualified_result(record, tx) do
    case {Basa.Witness.QES.package_check(record.cms, tx.basa_hash), record.qualification} do
      {:ok, :qualified} -> :ok
      {:ok, :not_qualified} -> :not_qualified
      {:ok, :unchecked} -> :pending
      {other, _} -> other
    end
  end

  defp in_person(%Transaction{mem_confirmed_at: nil}), do: []

  defp in_person(tx) do
    case Basa.Witness.MemAttest.confirmed_pair(tx) do
      {o, a} ->
        [
          {:in_person,
           Basa.Witness.MemAttest.pair_check(o.attestation, a.attestation, tx.basa_hash)}
        ]

      nil ->
        [{:in_person, {:error, :attestations_missing}}]
    end
  end

  defp timestamp(%Transaction{status: status}) when status in [:draft, :signing, :cancelled],
    do: []

  defp timestamp(%Transaction{timestamp_token: nil}), do: [{:timestamp, :pending}]

  defp timestamp(tx) do
    case Basa.Witness.Timestamp.verify(tx.timestamp_token, tx.basa_hash) do
      {:ok, _time} -> [{:timestamp, :ok}]
      {:error, reason} -> [{:timestamp, {:error, reason}}]
    end
  end

  defp acts(%Transaction{basa_hash: nil}, _parties), do: []

  defp acts(tx, parties) do
    keys = Map.new(parties, &{&1.role, &1.public_key})

    {checks, _} =
      Enum.map_reduce(Basa.Witness.Acts.chain(tx), tx.basa_hash, fn act, previous ->
        {{{:act, act.sequence}, act_result(tx, act, previous, keys)}, act.hash}
      end)

    checks
  end

  defp act_result(tx, act, previous, keys) do
    files = Basa.Witness.Acts.files(act.id)

    with {:ok, decoded} <- Crypto.decode_act(act.bytes),
         true <- Crypto.basa_hash(act.bytes) == act.hash || {:error, :hash_mismatch},
         true <-
           (decoded.basa_hash == tx.basa_hash and act.previous == previous and
              decoded.previous == previous) ||
             {:error, :chain_broken},
         true <-
           Enum.map(decoded.files, & &1.sha256) == Enum.map(files, & &1.sha256) ||
             {:error, :files_differ},
         true <-
           Enum.all?(files, &(Store.intact(&1, tx) == :ok)) || {:error, :file_changed},
         :ok <- act_signatures(act, keys) do
      :ok
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp act_signatures(%{author: :basa}, _keys), do: :ok
  defp act_signatures(%{status: :unsigned}, _keys), do: :ok

  defp act_signatures(act, keys) do
    other = if act.author == :offeror, do: :acceptor, else: :offeror

    cond do
      not Crypto.verify_act(keys[act.author], act.hash, act.author_signature) ->
        {:error, :bad_author_signature}

      act.kind == :settlement and act.status == :effective and
          not Crypto.verify_act(keys[other], act.hash, act.counter_signature) ->
        {:error, :bad_counter_signature}

      true ->
        :ok
    end
  end

  defp manifest_matches(m, tx, evidence, parties) do
    keys = Map.new(parties, &{to_string(&1.role), {&1.user_id, &1.public_key}})

    cond do
      m.transaction_id != tx.id ->
        {:error, :other_transaction}

      Enum.map(m.files, & &1.sha256) != Enum.map(evidence, & &1.sha256) ->
        {:error, :files_differ}

      Enum.any?(m.parties, &(keys[&1.role] != {&1.user_id, &1.public_key})) ->
        {:error, :parties_differ}

      true ->
        :ok
    end
  end

  defp log(tx, ok?, checks, opts) do
    failed = for {name, {:error, reason}} <- checks, do: "#{inspect(name)}: #{inspect(reason)}"

    Ash.create!(
      AccessLog,
      %{
        transaction_id: tx.id,
        action: :verify,
        actor_id: opts[:actor] && opts[:actor].id,
        reason: opts[:reason],
        result: if(ok?, do: "ok", else: "failed: " <> Enum.join(failed, "; "))
      },
      action: :record,
      authorize?: false
    )
  end
end
