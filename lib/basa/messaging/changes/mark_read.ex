defmodule Basa.Messaging.Changes.MarkRead do
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, context) do
    field =
      if context.actor.id == changeset.data.lessor_id, do: :lessor_unread, else: :lessee_unread

    Ash.Changeset.force_change_attribute(changeset, field, false)
  end
end
