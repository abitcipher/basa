defmodule Basa.Moderation.Changes.LevelChanged do
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    if Ash.Changeset.changing_attribute?(changeset, :moderation_level) do
      Ash.Changeset.after_action(changeset, fn _cs, settings ->
        Task.start(fn -> Basa.Moderation.set_level(settings.moderation_level) end)
        {:ok, settings}
      end)
    else
      changeset
    end
  end
end
