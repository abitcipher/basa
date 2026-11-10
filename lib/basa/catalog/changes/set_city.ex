defmodule Basa.Catalog.Changes.SetCity do
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    cond do
      Ash.Changeset.changing_attribute?(changeset, :city_id) ->
        case Basa.Geo.get(Ash.Changeset.get_attribute(changeset, :city_id)) do
          nil ->
            Ash.Changeset.add_error(changeset, field: :city_id, message: "is not a known city")

          city ->
            changeset
            |> Ash.Changeset.force_change_attribute(:city, city.name)
            |> Ash.Changeset.after_transaction(fn
              _cs, {:ok, room} ->
                Basa.Geo.picked(city)
                {:ok, room}

              _cs, other ->
                other
            end)
        end

      Ash.Changeset.changing_attribute?(changeset, :city) ->
        case Basa.Geo.find_by_name(Ash.Changeset.get_attribute(changeset, :city)) do
          nil -> Ash.Changeset.force_change_attribute(changeset, :city_id, nil)
          city -> Ash.Changeset.force_change_attribute(changeset, :city_id, city.id)
        end

      true ->
        changeset
    end
  end
end
