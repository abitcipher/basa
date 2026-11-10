defmodule Basa.Messaging.Changes.MarkUnreadForOther do
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    sender_id = Ash.Changeset.get_argument(changeset, :sender_id)
    field = if sender_id == changeset.data.lessor_id, do: :lessee_unread, else: :lessor_unread
    Ash.Changeset.force_change_attribute(changeset, field, true)
  end
end
