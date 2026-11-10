defmodule Basa.Witness.QES.CscProvider do
  @behaviour Basa.Witness.QES.Provider

  alias Basa.Witness.{Native, QES}

  @sha256_oid "2.16.840.1.101.3.4.2.1"
  @ecdsa_sha256 "1.2.840.10045.4.3.2"
  @rsa_sha256 "1.2.840.113549.1.1.11"

  defp config, do: Application.get_env(:basa, __MODULE__, [])

  @impl true
  def anchors do
    certs =
      case config()[:anchors] do
        {m, f, a} -> apply(m, f, a)
        list when is_list(list) -> list
        _ -> []
      end

    for c <- certs, do: %{certificate: c, provider: :csc, test?: config()[:test] == true}
  end

  @impl true
  def start(record, _tx, _party, return_url) do
    verifier = verifier()

    {:ok, authorize_url(record, return_url, verifier, %{"scope" => "service"}),
     %{"step" => "service", "verifier" => verifier}}
  end

  @impl true
  def complete(_record, %{"error" => _}), do: {:error, :cancelled}

  def complete(%{provider_data: %{"step" => "service"} = data} = record, %{"code" => code}) do
    tx = Ash.get!(Basa.Witness.Transaction, record.transaction_id, authorize?: false)

    with {:ok, token} <- token(code, data["verifier"], QES.return_url(record)),
         {:ok, cred} <- credential(token),
         {:ok, attrs} <- Native.qes_prepare(tx.basa_hash, hd(cred.certificates)) do
      hash = :crypto.hash(:sha256, attrs)
      verifier = verifier()

      url =
        authorize_url(record, QES.return_url(record), verifier, %{
          "scope" => "credential",
          "credentialID" => cred.id,
          "numSignatures" => "1",
          "hashes" => Base.url_encode64(hash, padding: false),
          "hashAlgorithmOID" => @sha256_oid
        })

      {:continue, url,
       %{
         "step" => "credential",
         "verifier" => verifier,
         "credential_id" => cred.id,
         "certificates" => Enum.map(cred.certificates, &Base.encode64/1),
         "algorithm" => cred.algorithm,
         "signed_attrs" => Base.encode64(attrs)
       }}
    end
  end

  def complete(%{provider_data: %{"step" => "credential"} = data} = record, %{"code" => code}) do
    attrs = Base.decode64!(data["signed_attrs"])
    hash = :crypto.hash(:sha256, attrs)
    certs = Enum.map(data["certificates"], &Base.decode64!/1)

    with {:ok, token} <- token(code, data["verifier"], QES.return_url(record)),
         {:ok, %{status: 200, body: %{"signatures" => [sig | _]}}} <-
           post(service("/signatures/signHash"), token, %{
             "credentialID" => data["credential_id"],
             "hashes" => [Base.encode64(hash)],
             "hashAlgorithmOID" => @sha256_oid,
             "signAlgo" => data["algorithm"]
           }),
         {:ok, signature} <- Base.decode64(sig) do
      Native.qes_assemble(certs, attrs, signature, data["algorithm"])
    else
      {:ok, %{status: status}} -> {:error, {:sign_hash, status}}
      {:error, _} = e -> e
      _ -> {:error, :bad_response}
    end
  end

  def complete(_record, _params), do: {:error, :bad_response}

  defp credential(token) do
    body = %{"credentialInfo" => true, "certificates" => "chain", "certInfo" => true}

    with {:ok, %{status: 200, body: %{"credentialInfos" => infos}}} <-
           post(service("/credentials/list"), token, body),
         %{} = info <- Enum.find(infos, &(get_in(&1, ["key", "status"]) == "enabled")),
         {:ok, certs} <- decode_all(get_in(info, ["cert", "certificates"]) || []),
         {:ok, algorithm} <- algorithm(get_in(info, ["key", "algo"]) || []) do
      {:ok, %{id: info["credentialID"], certificates: certs, algorithm: algorithm}}
    else
      nil -> {:error, :no_usable_credential}
      {:ok, %{status: status}} -> {:error, {:credentials_list, status}}
      other -> other
    end
  end

  defp algorithm(algos) do
    cond do
      Enum.any?(algos, &(&1 in ["1.2.840.10045.2.1", @ecdsa_sha256])) -> {:ok, @ecdsa_sha256}
      Enum.any?(algos, &(&1 in ["1.2.840.113549.1.1.1", @rsa_sha256])) -> {:ok, @rsa_sha256}
      true -> {:error, :unsupported_key}
    end
  end

  defp decode_all([]), do: {:error, :no_certificate}

  defp decode_all(list) do
    Enum.reduce_while(list, {:ok, []}, fn c, {:ok, acc} ->
      case Base.decode64(c) do
        {:ok, der} -> {:cont, {:ok, acc ++ [der]}}
        :error -> {:halt, {:error, :bad_certificate}}
      end
    end)
  end

  defp token(code, verifier, redirect_uri) do
    form = [
      grant_type: "authorization_code",
      code: code,
      client_id: config()[:client_id],
      client_secret: config()[:client_secret],
      redirect_uri: redirect_uri,
      code_verifier: verifier
    ]

    case Req.post(config()[:oauth_url] <> "/token", [form: form] ++ req_options()) do
      {:ok, %{status: 200, body: %{"access_token" => t}}} -> {:ok, t}
      {:ok, %{status: status}} -> {:error, {:token, status}}
      {:error, _} -> {:error, :unreachable}
    end
  end

  defp post(url, token, body) do
    case Req.post(url, [json: body, auth: {:bearer, token}] ++ req_options()) do
      {:ok, resp} -> {:ok, resp}
      {:error, _} -> {:error, :unreachable}
    end
  end

  defp authorize_url(record, redirect_uri, verifier, extra) do
    query =
      Map.merge(
        %{
          "response_type" => "code",
          "client_id" => config()[:client_id],
          "redirect_uri" => redirect_uri,
          "code_challenge" => Base.url_encode64(:crypto.hash(:sha256, verifier), padding: false),
          "code_challenge_method" => "S256",
          "state" => Base.url_encode64(record.state, padding: false)
        },
        extra
      )

    config()[:oauth_url] <> "/authorize?" <> URI.encode_query(query)
  end

  defp service(path), do: config()[:service_url] <> path
  defp verifier, do: Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)

  defp req_options,
    do: Keyword.merge([retry: false, receive_timeout: 10_000], config()[:req_options] || [])
end
