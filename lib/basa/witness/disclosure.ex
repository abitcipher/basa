defmodule Basa.Witness.Disclosure do
  require Ash.Query

  alias Basa.Witness.{Crypto, Evidence, Party, Store, Transaction}

  @format "basa-disclosure/1"

  def build(tx, positions, opts \\ [])

  def build(%Transaction{basa_hash: hash} = tx, positions, opts)
      when is_binary(hash) and is_list(positions) do
    evidence =
      Evidence
      |> Ash.Query.filter(transaction_id == ^tx.id and is_nil(act_id))
      |> Ash.Query.sort(position: :asc)
      |> Ash.read!(authorize?: false)

    hashes = Enum.map(evidence, & &1.sha256)
    parties = Party |> Ash.Query.filter(transaction_id == ^tx.id) |> Ash.read!(authorize?: false)
    chosen = Enum.filter(evidence, &(&1.position in positions))

    with true <- chosen != [] || {:error, :no_files},
         {:ok, files} <- files(chosen, tx, hashes, opts) do
      {:ok,
       %{
         "format" => @format,
         "basa_hash" => Crypto.to_text(hash),
         "manifest" => Base.encode64(tx.manifest),
         "signatures" =>
           for(
             p <- Enum.sort_by(parties, & &1.role),
             p.signature,
             do: %{"role" => to_string(p.role), "signature" => Base.encode64(p.signature)}
           ),
         "timestamp" => tx.timestamp_token && Base.encode64(tx.timestamp_token),
         "mem_attestations" => mem_attestations(tx),
         "qualified_signatures" => qualified_signatures(tx),
         "files" => files
       }}
    end
  end

  def build(_tx, _positions, _opts), do: {:error, :not_sealed}

  defp qualified_signatures(tx) do
    Basa.Witness.QualifiedSignature
    |> Ash.Query.filter(transaction_id == ^tx.id and status == :signed)
    |> Ash.Query.sort(signed_at: :desc)
    |> Ash.read!(authorize?: false)
    |> Enum.uniq_by(& &1.role)
    |> Enum.sort_by(&(&1.role != :offeror))
    |> Enum.map(&%{"role" => to_string(&1.role), "cms" => Base.encode64(&1.cms)})
  end

  defp mem_attestations(%Transaction{mem_confirmed_at: nil}), do: []

  defp mem_attestations(tx) do
    case Basa.Witness.MemAttest.confirmed_pair(tx) do
      {o, a} -> [Base.encode64(o.attestation), Base.encode64(a.attestation)]
      nil -> []
    end
  end

  defp files(chosen, tx, hashes, opts) do
    Enum.reduce_while(chosen, {:ok, []}, fn e, {:ok, acc} ->
      with {:ok, content} <- Store.read(e, tx, opts),
           {:ok, proof} <- Crypto.merkle_proof(hashes, e.position) do
        file = %{
          "index" => e.position,
          "kind" => to_string(e.kind),
          "media_type" => e.media_type,
          "content" => Base.encode64(content),
          "proof" => Enum.map(proof, &Base.encode64/1)
        }

        {:cont, {:ok, acc ++ [file]}}
      else
        error -> {:halt, error}
      end
    end)
  end

  def check(%{"format" => @format} = pkg) do
    with {:ok, manifest_bytes} <- b64(pkg["manifest"]),
         {:ok, claimed} <- Crypto.from_text(pkg["basa_hash"] || "") |> ok_or(:bad_basa_hash),
         {:ok, manifest} <- Crypto.decode_manifest(manifest_bytes) |> ok_or(:bad_manifest) do
      hash = Crypto.basa_hash(manifest_bytes)
      time = timestamp_time(pkg["timestamp"], hash)

      checks =
        [
          {:basa_hash, if(hash == claimed, do: :ok, else: {:error, :mismatch})},
          {:timestamp, time_result(time)}
        ] ++
          signatures(pkg["signatures"] || [], manifest, hash) ++
          in_person(pkg["mem_attestations"] || [], hash) ++
          qualified(pkg["qualified_signatures"] || [], hash) ++
          file_checks(pkg["files"] || [], manifest)

      %{
        ok?:
          Enum.all?(checks, fn {name, r} ->
            r in [:ok, :test] or (name == :timestamp and r == :missing)
          end),
        basa_hash: Crypto.to_text(hash),
        time: match?({:ok, _}, time) && elem(time, 1),
        manifest: manifest,
        checks: checks
      }
    else
      {:error, reason} -> %{ok?: false, checks: [{:package, {:error, reason}}]}
    end
  end

  def check(_), do: %{ok?: false, checks: [{:package, {:error, :unknown_format}}]}

  def check_json(text) do
    case Jason.decode(text) do
      {:ok, pkg} -> check(pkg)
      {:error, _} -> %{ok?: false, checks: [{:package, {:error, :not_json}}]}
    end
  end

  defp signatures(sigs, manifest, hash) do
    for party <- manifest.parties do
      role = party.role
      sig = Enum.find(sigs, &(&1["role"] == role))

      result =
        with %{"signature" => s} <- sig,
             {:ok, bytes} <- b64(s),
             true <- Crypto.verify_seal(party.public_key, hash, bytes) do
          :ok
        else
          nil -> :missing
          _ -> {:error, :bad_signature}
        end

      {{:signature, role}, result}
    end
  end

  defp qualified(list, hash) when is_list(list) do
    for item <- list do
      role = is_map(item) && item["role"]

      result =
        with %{"cms" => cms} <- item,
             {:ok, bytes} <- b64(cms) do
          Basa.Witness.QES.package_check(bytes, hash)
        else
          _ -> {:error, :bad_signature}
        end

      {{:qualified, to_string(role)}, result}
    end
  end

  defp qualified(_, _hash), do: [{{:qualified, ""}, {:error, :bad_signature}}]

  defp in_person([], _hash), do: []

  defp in_person([o, a], hash) when is_binary(o) and is_binary(a) do
    result =
      with {:ok, ob} <- b64(o),
           {:ok, ab} <- b64(a),
           do: Basa.Witness.MemAttest.pair_check(ob, ab, hash)

    [{:in_person, result}]
  end

  defp in_person(_, _hash), do: [{:in_person, {:error, :mismatch}}]

  defp file_checks(files, manifest) do
    size = length(manifest.files)

    for f <- files do
      index = f["index"]
      entry = is_integer(index) && Enum.at(manifest.files, index)

      result =
        with %{} <- entry || {:error, :no_such_file},
             {:ok, content} <- b64(f["content"]),
             {:ok, proof} <- proof(f["proof"]),
             hash = Crypto.hash(content),
             true <- hash == entry.sha256 || {:error, :content_differs},
             true <-
               Crypto.merkle_verify(manifest.merkle_root, hash, index, size, proof) ||
                 {:error, :bad_proof} do
          :ok
        end

      {{:file, index}, result}
    end
  end

  defp proof(list) when is_list(list) do
    Enum.reduce_while(list, {:ok, []}, fn p, {:ok, acc} ->
      case b64(p) do
        {:ok, b} -> {:cont, {:ok, acc ++ [b]}}
        error -> {:halt, error}
      end
    end)
  end

  defp proof(_), do: {:error, :bad_proof}

  defp timestamp_time(nil, _hash), do: :missing

  defp timestamp_time(token, hash) do
    with {:ok, bytes} <- b64(token), do: Basa.Witness.Timestamp.verify(bytes, hash)
  end

  defp time_result({:ok, _}), do: :ok
  defp time_result(:missing), do: :missing
  defp time_result({:error, reason}), do: {:error, reason}

  defp b64(s) when is_binary(s) do
    case Base.decode64(s) do
      {:ok, b} -> {:ok, b}
      :error -> {:error, :bad_base64}
    end
  end

  defp b64(_), do: {:error, :bad_base64}

  defp ok_or({:ok, v}, _), do: {:ok, v}
  defp ok_or(_, reason), do: {:error, reason}
end
