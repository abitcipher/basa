defmodule Basa.Messaging.Changes.SetLessor do
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      lot_id = Ash.Changeset.get_attribute(changeset, :lot_id)

      case lot_id && Ash.get(Basa.Catalog.Lot, lot_id, authorize?: false) do
        {:ok, %{owner_id: owner_id}} when owner_id == context.actor.id ->
          Ash.Changeset.add_error(changeset,
            field: :lot_id,
            message: Basa.I18n.t("is your own offer")
          )

        {:ok, %{state: :published, owner_id: owner_id}} ->
          Ash.Changeset.force_change_attribute(changeset, :lessor_id, owner_id)

        _ ->
          Ash.Changeset.add_error(changeset,
            field: :lot_id,
            message: Basa.I18n.t("is not available")
          )
      end
    end)
  end
end
