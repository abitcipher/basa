defmodule Basa.Storage do
  @callback put(key :: String.t(), body :: binary(), content_type :: String.t()) ::
              :ok | {:error, term()}
  @callback get(key :: String.t()) :: {:ok, binary(), String.t()} | {:error, :not_found | term()}
  @callback ensure_bucket() :: :ok | {:error, term()}

  def put(key, body, content_type), do: adapter().put(key, body, content_type)
  def get(key), do: adapter().get(key)
  def ensure_bucket, do: adapter().ensure_bucket()

  def store(prefix, body, content_type) do
    key = "#{prefix}/#{Ecto.UUID.generate()}#{extension(content_type)}"

    with :ok <- put(key, body, content_type) do
      if String.starts_with?(to_string(content_type), "image/"), do: Basa.Moderation.queue(key)
      {:ok, key}
    end
  end

  def url(nil), do: nil
  def url(key), do: "/media/" <> key

  def bucket("stock/" <> _), do: config()[:stock_bucket] || "basa-stock"
  def bucket(_key), do: config()[:bucket] || "basa-media"

  def buckets, do: Enum.uniq([bucket(""), bucket("stock/")])

  def config, do: Application.get_env(:basa, __MODULE__, [])
  defp adapter, do: Keyword.get(config(), :adapter, Basa.Storage.Local)

  defp extension("image/jpeg"), do: ".jpg"
  defp extension("image/png"), do: ".png"
  defp extension("image/webp"), do: ".webp"
  defp extension("image/gif"), do: ".gif"
  defp extension(_), do: ""
end
