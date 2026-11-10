defmodule Basa.Catalog.Changes.FetchPhotos do
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, context) do
    case Ash.Changeset.get_argument(changeset, :photo_urls) do
      nil ->
        changeset

      urls ->
        Ash.Changeset.before_transaction(changeset, fn changeset ->
          owner_id = changeset.data.owner_id || (context.actor && context.actor.id)
          keys = Basa.Catalog.Photos.fetch(urls, owner_id, http: true)
          Ash.Changeset.force_change_attribute(changeset, :photos, keys)
        end)
    end
  end
end
