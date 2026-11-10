defmodule Basa.Witness.QES.DevProvider do
  @behaviour Basa.Witness.QES.Provider

  alias Basa.Witness.{Native, QES}

  @impl true
  def anchors do
    {:ok, ca} = Native.qes_dev_ca(seed())
    [%{certificate: ca, provider: :dev, test?: true}]
  end

  @impl true
  def start(record, _tx, _party, _return_url),
    do: {:ok, "/dev/qes/" <> Base.url_encode64(record.state, padding: false)}

  @impl true
  def complete(_record, %{"cms" => cms}) when is_binary(cms) do
    case Base.url_decode64(cms, padding: false) do
      {:ok, bytes} -> {:ok, bytes}
      :error -> {:error, :bad_response}
    end
  end

  def complete(_record, %{"error" => _}), do: {:error, :cancelled}
  def complete(_record, _params), do: {:error, :bad_response}

  def sign(user_id, name, basa_hash), do: Native.qes_dev_sign(seed(), user_id, name, basa_hash)

  def return_with(record, cms),
    do: QES.return_url(record) <> "?cms=" <> Base.url_encode64(cms, padding: false)

  defp seed do
    secret = BasaWeb.Endpoint.config(:secret_key_base)
    :crypto.mac(:hmac, :sha256, secret, "BASA dev QES")
  end
end
