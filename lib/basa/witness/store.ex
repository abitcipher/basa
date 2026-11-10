defmodule Basa.Witness.Store do
  require Ash.Query

  alias Basa.Witness.{Act, Crypto, Evidence, KeyShare, Party, Transaction}

  @kinds [:contract, :photo, :voice, :other]

  def add(%Transaction{} = tx, kind, media_type, body, added_by \\ nil, opts \\ [])
      when kind in @kinds and is_binary(body) do
    file_hash = Crypto.hash(body)
    act = opts[:act]

    with :ok <- open_for_files(tx, act),
         {:ok, key} <- key(tx, act: act),
         :ok <- check(key, body, act || tx),
         {:ok, stored} <- stored_form(tx, key, body),
         storage_key = storage_key(tx, act, file_hash),
         :ok <- Basa.Storage.put(storage_key, stored, stored_type(tx, media_type)) do
      Ash.create(
        Evidence,
        %{
          transaction_id: tx.id,
          act_id: act && act.id,
          position: next_position(tx, act),
          kind: kind,
          media_type: media_type,
          size: byte_size(body),
          sha256: file_hash,
          stored_sha256: Crypto.hash(stored),
          storage_key: storage_key,
          added_by_id: added_by && added_by.id
        },
        action: :record,
        authorize?: false
      )
    end
  end

  def read(%Evidence{} = evidence, %Transaction{} = tx, opts \\ []) do
    with {:ok, stored, _type} <- Basa.Storage.get(evidence.storage_key),
         {:ok, plain} <- readable(tx, evidence, stored, opts) do
      if Crypto.hash(plain) == evidence.sha256, do: {:ok, plain}, else: {:error, :changed}
    end
  end

  def intact(%Evidence{stored_sha256: nil} = evidence, tx) do
    case read(evidence, tx) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  def intact(%Evidence{} = evidence, _tx) do
    case Basa.Storage.get(evidence.storage_key) do
      {:ok, stored, _type} ->
        if Crypto.hash(stored) == evidence.stored_sha256, do: :ok, else: {:error, :changed}

      {:error, _} ->
        {:error, :missing}
    end
  end

  def key(%Transaction{} = tx, opts \\ []) do
    act = opts[:act]
    rows = shares(tx, act)
    readable = for r <- rows, r.share, into: %{}, do: {r.owner, r.share}

    pair =
      case opts[:share] do
        nil -> Enum.take(Map.values(readable), 2)
        given -> [given | Enum.take(for({:basa, s} <- readable, do: s), 1)]
      end

    with true <- length(pair) == 2 || {:error, :shares_missing},
         {:ok, key} <- Crypto.combine(pair) do
      {:ok,
       %{
         key: key,
         shares: readable,
         recovery: if(act, do: act.recovery_sealed, else: tx.recovery_sealed)
       }}
    end
  end

  def new_act_key(%Act{} = act) do
    public = Basa.Witness.recovery_public_key()

    with {:ok, key} <- Crypto.new_key(act.id, public) do
      for {owner, share} <- key.shares do
        Ash.create!(
          KeyShare,
          %{owner: owner, share: share, act_id: act.id, transaction_id: act.transaction_id},
          action: :store,
          authorize?: false
        )
      end

      Ash.update(act, %{recovery_sealed: key.recovery}, action: :set_recovery, authorize?: false)
    end
  end

  def deliver(%Transaction{} = tx, opts \\ []) do
    act = opts[:act]
    aad = if act, do: act.id, else: tx.id

    keys =
      Party
      |> Ash.Query.filter(transaction_id == ^tx.id)
      |> Ash.read!(authorize?: false)
      |> Map.new(&{&1.role, &1.box_key})

    for row <- shares(tx, act),
        row.owner in [:offeror, :acceptor],
        row.share,
        keys[row.owner] do
      {:ok, sealed} = Crypto.seal_for_device(keys[row.owner], row.share, aad)

      Ash.update!(
        row,
        %{
          sealed_share: sealed,
          delivered_at: DateTime.utc_now(),
          share: if(tx.storage_mode == :encrypted, do: nil, else: row.share)
        },
        action: :deliver,
        authorize?: false
      )
    end

    :ok
  end

  def sealed_share(%Transaction{} = tx, role, act \\ nil) do
    tx |> shares(act) |> Enum.find(&(&1.owner == role)) |> then(&(&1 && &1.sealed_share))
  end

  def check(key, body, owner) do
    opts =
      case Basa.Witness.recovery_private_key() do
        nil -> []
        private -> [recovery_private_key: private, transaction_id: owner.id]
      end

    case Crypto.key_check(key, body, opts) do
      :ok -> :ok
      {:error, failures} -> {:error, {:key_check_failed, failures}}
    end
  end

  defp shares(tx, nil) do
    KeyShare
    |> Ash.Query.filter(transaction_id == ^tx.id and is_nil(act_id))
    |> Ash.read!(authorize?: false)
  end

  defp shares(_tx, act) do
    KeyShare |> Ash.Query.filter(act_id == ^act.id) |> Ash.read!(authorize?: false)
  end

  defp open_for_files(%Transaction{status: :draft}, nil), do: :ok
  defp open_for_files(_tx, nil), do: {:error, :not_a_draft}
  defp open_for_files(%Transaction{id: id}, %{status: :draft, transaction_id: id}), do: :ok
  defp open_for_files(_tx, _act), do: {:error, :not_a_draft}

  defp stored_form(%Transaction{storage_mode: :plain}, _key, body), do: {:ok, body}

  defp stored_form(%Transaction{storage_mode: :encrypted}, key, body),
    do: Crypto.encrypt(key.key, body)

  defp readable(%Transaction{storage_mode: :plain}, _evidence, stored, _opts), do: {:ok, stored}

  defp readable(%Transaction{storage_mode: :encrypted} = tx, evidence, stored, opts) do
    act = evidence.act_id && Ash.get!(Act, evidence.act_id, authorize?: false)

    with {:ok, key} <- key(tx, act: act, share: opts[:share]),
         do: Crypto.decrypt(key.key, stored, evidence.sha256)
  end

  defp stored_type(%Transaction{storage_mode: :plain}, media_type), do: media_type
  defp stored_type(_, _), do: "application/octet-stream"

  defp storage_key(tx, act, file_hash),
    do:
      "witness/#{tx.id}/#{if(act, do: act.id, else: "contract")}/#{Base.encode16(file_hash, case: :lower)}"

  defp next_position(tx, nil) do
    Evidence
    |> Ash.Query.filter(transaction_id == ^tx.id and is_nil(act_id))
    |> Ash.count!(authorize?: false)
  end

  defp next_position(_tx, act) do
    Evidence
    |> Ash.Query.filter(act_id == ^act.id)
    |> Ash.count!(authorize?: false)
  end
end
