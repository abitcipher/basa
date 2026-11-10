defmodule BasaWeb.PhotoOrder do
  def move(photos, key, dir) do
    case Enum.find_index(photos, &(&1 == key)) do
      nil ->
        photos

      i ->
        j = if dir == "left", do: i - 1, else: i + 1

        if j < 0 or j >= length(photos),
          do: photos,
          else: photos |> List.replace_at(i, Enum.at(photos, j)) |> List.replace_at(j, key)
    end
  end

  def reorder(photos, keys) when is_list(keys) do
    if Enum.sort(keys) == Enum.sort(photos), do: keys, else: photos
  end

  def reorder(photos, _keys), do: photos
end
