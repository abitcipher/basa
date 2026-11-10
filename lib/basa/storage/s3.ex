defmodule Basa.Storage.S3 do
  @behaviour Basa.Storage

  @impl true
  def put(key, body, content_type) do
    case Req.put(req(),
           url: object_url(key),
           body: body,
           headers: [{"content-type", content_type}]
         ) do
      {:ok, %{status: status}} when status in 200..299 -> :ok
      {:ok, resp} -> {:error, {:http, resp.status, resp.body}}
      error -> error
    end
  end

  @impl true
  def get(key) do
    case Req.get(req(), url: object_url(key), decode_body: false) do
      {:ok, %{status: 200} = resp} ->
        {:ok, resp.body,
         resp |> Req.Response.get_header("content-type") |> List.first("application/octet-stream")}

      {:ok, %{status: 404}} ->
        {:error, :not_found}

      {:ok, resp} ->
        {:error, {:http, resp.status}}

      error ->
        error
    end
  end

  @impl true
  def ensure_bucket do
    Enum.reduce_while(Basa.Storage.buckets(), :ok, fn bucket, :ok ->
      case Req.put(req(), url: "#{endpoint()}/#{bucket}") do
        {:ok, %{status: status}} when status in [200, 409] -> {:cont, :ok}
        {:ok, resp} -> {:halt, {:error, {:http, resp.status, resp.body}}}
        error -> {:halt, error}
      end
    end)
  end

  defp req do
    c = Basa.Storage.config()

    Req.new(
      aws_sigv4: [
        access_key_id: c[:access_key],
        secret_access_key: c[:secret_key],
        region: c[:region] || "us-east-1",
        service: :s3
      ],
      retry: :transient
    )
  end

  defp object_url(key), do: "#{endpoint()}/#{Basa.Storage.bucket(key)}/#{key}"
  defp endpoint, do: Basa.Storage.config()[:endpoint]
end
