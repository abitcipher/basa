defmodule Basa.Storage.Local do
  @behaviour Basa.Storage

  @impl true
  def put(key, body, content_type) do
    path = path(key)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, body)
    File.write!(path <> ".type", content_type)
    :ok
  end

  @impl true
  def get(key) do
    path = path(key)

    with {:ok, body} <- File.read(path),
         {:ok, type} <- File.read(path <> ".type") do
      {:ok, body, type}
    else
      _ -> {:error, :not_found}
    end
  end

  @impl true
  def ensure_bucket, do: :ok

  defp path(key) do
    root = Basa.Storage.config()[:root] || Path.join(System.tmp_dir!(), "basa-media")
    safe = key |> Path.split() |> Enum.reject(&(&1 in ["..", "/"])) |> Path.join()
    Path.join(root, safe)
  end
end
