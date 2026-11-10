defmodule Basa.Witness.QES.Dss do
  @path "/services/rest/validation/validateSignature"

  @type result :: %{
          qualified?: boolean(),
          indication: String.t() | nil,
          sub_indication: String.t() | nil,
          level: String.t() | nil,
          format: String.t() | nil,
          report: map()
        }

  defp config, do: Application.get_env(:basa, __MODULE__, [])

  def configured?, do: is_binary(config()[:url])

  @spec validate(binary(), binary()) :: {:ok, result()} | {:error, term()}
  def validate(cms, basa_hash) when is_binary(cms) and is_binary(basa_hash) do
    cond do
      not configured?() -> {:error, :not_configured}
      Basa.Services.switched_off?(:qes) -> {:error, :switched_off}
      true -> request(cms, basa_hash)
    end
  end

  def retry?(:unreachable), do: true
  def retry?({:http, _}), do: true
  def retry?(_), do: false

  defp request(cms, hash) do
    body = %{
      "signedDocument" => %{"bytes" => Base.encode64(cms), "name" => "signature.p7s"},
      "originalDocuments" => [
        %{"bytes" => Base.encode64(hash), "digestAlgorithm" => "SHA256", "name" => "contract"}
      ],
      "tokenExtractionStrategy" => "NONE"
    }

    options = Keyword.merge([retry: false, receive_timeout: 30_000], config()[:req_options] || [])

    case Req.post(config()[:url] <> @path, [json: body] ++ options) do
      {:ok, %{status: 200, body: %{} = resp}} -> parse(resp)
      {:ok, %{status: status}} -> {:error, {:http, status}}
      {:error, _} -> {:error, :unreachable}
    end
  end

  @doc false
  def parse(%{"SimpleReport" => %{"signatureOrTimestampOrEvidenceRecord" => tokens}}) do
    case for(%{"Signature" => %{} = s} <- tokens || [], do: s) do
      [s] ->
        indication = s["Indication"]
        level = get_in(s, ["SignatureLevel", "value"])

        {:ok,
         %{
           qualified?: indication == "TOTAL_PASSED" and level == "QESig",
           indication: indication,
           sub_indication: s["SubIndication"],
           level: level,
           format: s["SignatureFormat"],
           report: Map.take(s, ~w(SignedBy SigningTime BestSignatureTime Indication SubIndication
                                  SignatureLevel SignatureFormat AdESValidationDetails
                                  QualificationDetails CertificateChain))
         }}

      _ ->
        {:error, :bad_response}
    end
  end

  def parse(_), do: {:error, :bad_response}
end
