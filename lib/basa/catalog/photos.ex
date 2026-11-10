defmodule Basa.Catalog.Photos do
  @max 6

  def max, do: @max

  @spec fetch([String.t()], String.t(), keyword()) :: [String.t()]
  def fetch(urls, owner_id, opts \\ []) do
    urls
    |> Enum.uniq()
    |> Enum.take(@max)
    |> Task.async_stream(&Basa.Images.Fetch.image(&1, opts),
      timeout: 30_000,
      on_timeout: :kill_task,
      max_concurrency: 3
    )
    |> Enum.flat_map(fn
      {:ok, {:ok, body, type}} ->
        case Basa.Storage.store("items/#{owner_id}", body, type) do
          {:ok, key} -> [key]
          _ -> []
        end

      _ ->
        []
    end)
  end
end
