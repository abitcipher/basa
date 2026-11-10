defmodule Basa.Catalog.Changes.ReviewLot do
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      lot = Ash.load!(changeset.data, [:room, basket: [:items, :attendants]], authorize?: false)

      case Basa.Rules.review_lot(lot) do
        :approve ->
          changeset
          |> AshStateMachine.transition_state(:published)
          |> Ash.Changeset.force_change_attribute(:published_at, DateTime.utc_now())
          |> Ash.Changeset.force_change_attribute(:review_note, nil)

        {:reject, reasons} ->
          changeset
          |> AshStateMachine.transition_state(:draft)
          |> Ash.Changeset.force_change_attribute(:review_note, Enum.join(reasons, "\n"))

        :manual ->
          changeset
          |> AshStateMachine.transition_state(:under_review)
          |> Ash.Changeset.force_change_attribute(:review_note, nil)
      end
    end)
  end
end
