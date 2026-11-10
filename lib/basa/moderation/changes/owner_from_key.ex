defmodule Basa.Moderation.Changes.OwnerFromKey do
  use Ash.Resource.Change

  @prefixes ~w(items rooms entrance street)

  @impl true
  def change(changeset, _opts, _context) do
    case owner(Ash.Changeset.get_attribute(changeset, :key)) do
      nil -> changeset
      id -> Ash.Changeset.force_change_attribute(changeset, :owner_id, id)
    end
  end

  def owner(key) when is_binary(key) do
    with [prefix, id | _] when prefix in @prefixes <- String.split(key, "/"),
         {:ok, uuid} <- Ecto.UUID.cast(id) do
      uuid
    else
      _ -> nil
    end
  end

  def owner(_), do: nil
end
