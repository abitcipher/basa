defmodule Basa.Witness.Manifest do
  require Ash.Query

  alias Basa.Witness.{Crypto, Evidence, Party, Transaction}

  def build(%Transaction{} = tx, created_at \\ DateTime.utc_now()) do
    parties = Party |> Ash.Query.filter(transaction_id == ^tx.id) |> Ash.read!(authorize?: false)

    evidence =
      Evidence
      |> Ash.Query.filter(transaction_id == ^tx.id and is_nil(act_id))
      |> Ash.Query.sort(position: :asc)
      |> Ash.read!(authorize?: false)

    by_role = Map.new(parties, &{&1.role, &1})

    manifest = %{
      transaction_id: tx.id,
      contract_type: to_string(tx.contract_type),
      template: tx.template,
      jurisdiction: to_string(tx.jurisdiction),
      consumer: tx.consumer,
      parties:
        for role <- [:offeror, :acceptor] do
          p = by_role[role]
          %{role: to_string(role), user_id: p.user_id, public_key: p.public_key}
        end,
      files:
        for e <- evidence do
          %{sha256: e.sha256, kind: to_string(e.kind), size: e.size, media_type: e.media_type}
        end,
      created_at: created_at |> DateTime.truncate(:second) |> DateTime.to_iso8601(),
      geo: nil
    }

    with {:ok, bytes} <- Crypto.encode_manifest(manifest) do
      {:ok, bytes, Crypto.basa_hash(bytes)}
    end
  end
end
