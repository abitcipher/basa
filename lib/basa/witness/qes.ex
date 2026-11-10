defmodule Basa.Witness.QES do
  alias Basa.Witness.{Native, Party, QualifiedSignature, Transaction}

  @providers %{dev: Basa.Witness.QES.DevProvider, csc: Basa.Witness.QES.CscProvider}

  defp known do
    extra = :basa |> Application.get_env(__MODULE__, []) |> Keyword.get(:modules, %{})
    Map.merge(@providers, extra)
  end

  def providers, do: if(Basa.Services.switched_off?(:qes), do: [], else: configured_providers())

  def configured_providers do
    known = known()

    :basa
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:providers, [])
    |> Enum.filter(&Map.has_key?(known, &1))
  end

  def provider(id) when is_atom(id), do: if(id in providers(), do: known()[id])

  def provider(_), do: nil

  def anchors do
    known = known()
    Enum.flat_map(configured_providers(), fn id -> known[id].anchors() end)
  end

  def return_url(%QualifiedSignature{state: state}),
    do: BasaWeb.Endpoint.url() <> "/qes/return/" <> Base.url_encode64(state, padding: false)

  def state_from_token(token) do
    case Base.url_decode64(token, padding: false) do
      {:ok, <<_::binary-size(16)>> = s} -> {:ok, s}
      _ -> :error
    end
  end

  def check(cms, %Transaction{basa_hash: hash}) when is_binary(cms) and is_binary(hash) do
    with {:ok, v} <- verify(cms, hash),
         %{} = anchor <-
           Enum.find(anchors(), &Native.qes_issued_by(v.certificate, &1.certificate)) ||
             {:error, :unknown_issuer} do
      {:ok, Map.put(v, :test?, anchor.test?)}
    end
  end

  def check(_, _), do: {:error, :not_sealed}

  def package_check(cms, hash) do
    case verify(cms, hash) do
      {:ok, v} ->
        case Enum.find(anchors(), &Native.qes_issued_by(v.certificate, &1.certificate)) do
          %{test?: true} -> :test
          %{} -> :ok
          nil -> {:error, :unknown_issuer}
        end

      {:error, {:invalid, "signed a different document"}} ->
        {:error, :mismatch}

      {:error, _} ->
        {:error, :bad_signature}
    end
  end

  def verify(cms, hash) do
    case Native.qes_verify(cms, hash) do
      {:ok, v} -> {:ok, v}
      {:error, reason} -> {:error, {:invalid, reason}}
    end
  end

  def qualification(cms, %Transaction{basa_hash: hash}) do
    case Basa.Witness.QES.Dss.validate(cms, hash) do
      {:ok, r} ->
        {%{
           qualification: if(r.qualified?, do: :qualified, else: :not_qualified),
           qualification_level: r.level,
           qualification_indication: r.indication,
           qualification_report: r.report,
           qualification_checked_at: DateTime.utc_now()
         }, false}

      {:error, reason} ->
        {%{qualification: :unchecked}, Basa.Witness.QES.Dss.retry?(reason)}
    end
  end

  defdelegate signed_pair(tx_id), to: Basa.Witness.QES.Complete

  def name_matches?(subject, %Party{legal_name: legal}) when is_binary(legal),
    do: normalize(subject) == normalize(legal)

  def name_matches?(_, _), do: false

  defp normalize(s),
    do: s |> String.downcase() |> String.replace(~r/[^\p{L}\p{N}]+/u, " ") |> String.trim()

  defmodule Provider do
    @callback anchors() :: [map()]

    @callback start(
                record :: Basa.Witness.QualifiedSignature.t(),
                tx :: Basa.Witness.Transaction.t(),
                party :: Basa.Witness.Party.t(),
                return_url :: String.t()
              ) :: {:ok, String.t()} | {:ok, String.t(), map()} | {:error, term()}

    @callback complete(record :: Basa.Witness.QualifiedSignature.t(), params :: map()) ::
                {:ok, binary()} | {:continue, String.t(), map()} | {:error, term()}
  end
end
