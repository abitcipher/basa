defmodule Basa.Witness.Recovery do
  require Ash.Query

  alias Basa.Witness.{Act, AuthorityRequest, Crypto, Evidence, Party, Transaction}

  @format "basa-recovery-kit/1"

  def kit(%AuthorityRequest{status: status} = request, actor)
      when status in [:approved, :opened] do
    tx = Ash.get!(Transaction, request.transaction_id, authorize?: false)
    acts = Act |> Ash.Query.filter(transaction_id == ^tx.id) |> Ash.read!(authorize?: false)
    act_keys = for a <- acts, a.recovery_sealed, into: %{}, do: {a.id, a.recovery_sealed}

    files =
      Evidence
      |> Ash.Query.filter(transaction_id == ^tx.id)
      |> Ash.Query.sort(position: :asc)
      |> Ash.read!(authorize?: false)
      |> Enum.sort_by(&{&1.act_id != nil, &1.act_id, &1.position})
      |> Enum.map(fn e ->
        {:ok, stored, _type} = Basa.Storage.get(e.storage_key)

        %{
          "act_id" => e.act_id,
          "key" => if(Map.has_key?(act_keys, e.act_id), do: e.act_id, else: tx.id),
          "index" => e.position,
          "kind" => to_string(e.kind),
          "media_type" => e.media_type,
          "sha256" => hex(e.sha256),
          "stored" => Base.encode64(stored)
        }
      end)

    parties = Party |> Ash.Query.filter(transaction_id == ^tx.id) |> Ash.read!(authorize?: false)

    kit = %{
      "format" => @format,
      "request" => %{
        "id" => request.id,
        "authority" => request.authority,
        "basis" => to_string(request.basis),
        "reference" => request.reference
      },
      "transaction_id" => tx.id,
      "storage_mode" => to_string(tx.storage_mode),
      "basa_hash" => Crypto.to_text(tx.basa_hash),
      "manifest" => Base.encode64(tx.manifest),
      "signatures" =>
        for(
          p <- parties,
          p.signature,
          do: %{"role" => to_string(p.role), "signature" => Base.encode64(p.signature)}
        ),
      "timestamp" => tx.timestamp_token && Base.encode64(tx.timestamp_token),
      "keys" =>
        [%{"id" => tx.id, "sealed" => tx.recovery_sealed && Base.encode64(tx.recovery_sealed)}] ++
          for({id, sealed} <- act_keys, do: %{"id" => id, "sealed" => Base.encode64(sealed)}),
      "files" => files
    }

    with {:ok, _} <- Basa.Witness.record_kit_export(request, actor: actor), do: {:ok, kit}
  end

  def kit(_request, _actor), do: {:error, :not_approved}

  def open_kit(%{"format" => @format} = kit, recovery_private_key) do
    with {:ok, keys} <- keys(kit, recovery_private_key) do
      check = Basa.Witness.Disclosure.check(disclosure_part(kit))

      lines =
        for f <- kit["files"] do
          {:ok, stored} = Base.decode64(f["stored"])
          hash = unhex(f["sha256"])

          content =
            case kit["storage_mode"] do
              "plain" -> {:ok, stored}
              _ -> Crypto.decrypt(keys[f["key"]], stored, hash)
            end

          result =
            case content do
              {:ok, c} -> if Crypto.hash(c) == hash, do: :ok, else: :changed
              {:error, _} -> :cannot_open
            end

          {name(f), elem(content, 1), result, f}
        end

      manifest_hashes =
        case check do
          %{manifest: %{files: files}} -> Enum.map(files, & &1.sha256)
          _ -> []
        end

      report = %{
        "format" => "basa-recovery-report/1",
        "request" => kit["request"],
        "transaction_id" => kit["transaction_id"],
        "basa_hash" => kit["basa_hash"],
        "contract" => %{
          "authentic" => check.ok?,
          "sealed_by" => check[:time] && DateTime.to_iso8601(check.time),
          "checks" => Enum.map(check.checks, fn {n, r} -> "#{inspect(n)}: #{inspect(r)}" end)
        },
        "files" =>
          for {name, _content, result, f} <- lines do
            in_manifest =
              f["act_id"] == nil and Enum.at(manifest_hashes, f["index"]) == unhex(f["sha256"])

            %{
              "name" => name,
              "sha256" => f["sha256"],
              "result" => to_string(result),
              "in_signed_manifest" => in_manifest
            }
          end
      }

      files = for {name, content, :ok, _} <- lines, do: %{name: name, content: content}
      {:ok, %{files: files, report: report}}
    end
  end

  def open_kit(_kit, _key), do: {:error, :not_a_kit}

  def report_json(report) do
    json = Jason.encode!(report, pretty: true) <> "\n"
    {json, hex(Crypto.hash(json))}
  end

  def split_key(private), do: Basa.Witness.Native.split(private)

  def combine_key(parts), do: Crypto.combine(parts)

  defp keys(kit, private) do
    Enum.reduce_while(kit["keys"], {:ok, %{}}, fn
      %{"sealed" => nil}, acc ->
        {:cont, acc}

      %{"id" => id, "sealed" => sealed}, {:ok, acc} ->
        case Crypto.recover(private, Base.decode64!(sealed), id) do
          {:ok, key} -> {:cont, {:ok, Map.put(acc, id, key)}}
          {:error, _} -> {:halt, {:error, :wrong_recovery_key}}
        end
    end)
  end

  defp disclosure_part(kit) do
    %{
      "format" => "basa-disclosure/1",
      "basa_hash" => kit["basa_hash"],
      "manifest" => kit["manifest"],
      "signatures" => kit["signatures"],
      "timestamp" => kit["timestamp"],
      "files" => []
    }
  end

  defp name(f) do
    where = if f["act_id"], do: "act-#{String.slice(f["act_id"], 0, 8)}", else: "contract"
    "#{where}-#{f["kind"]}-#{f["index"] + 1}#{ext(f["media_type"])}"
  end

  defp ext("application/pdf"), do: ".pdf"
  defp ext("image/jpeg"), do: ".jpg"
  defp ext("image/png"), do: ".png"
  defp ext("image/webp"), do: ".webp"
  defp ext("audio/webm"), do: ".webm"
  defp ext("audio/ogg"), do: ".ogg"
  defp ext("audio/mp4"), do: ".m4a"
  defp ext(_), do: ""

  defp hex(b), do: Base.encode16(b, case: :lower)
  defp unhex(s), do: Base.decode16!(s, case: :lower)
end
