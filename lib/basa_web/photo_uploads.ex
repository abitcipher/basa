defmodule BasaWeb.PhotoUploads do
  use Gettext, backend: BasaWeb.Gettext

  def store(socket, entry, prefix, count, max) do
    if count >= max do
      Phoenix.LiveView.consume_uploaded_entry(socket, entry, fn _ -> {:ok, nil} end)
      :full
    else
      key =
        Phoenix.LiveView.consume_uploaded_entry(socket, entry, fn %{path: path} ->
          {:ok, _key} = Basa.Storage.store(prefix, File.read!(path), entry.client_type)
        end)

      {:stored, key}
    end
  end

  def notice(max),
    do: gettext("Up to %{max} photos. The extra ones were not added.", max: max)
end
