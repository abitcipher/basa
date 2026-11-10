defmodule Basa.System.Changes.CatchUp do
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    before = changeset.data.services_off || []

    Ash.Changeset.after_action(changeset, fn _cs, settings ->
      Enum.each(before -- settings.services_off, &Basa.Services.caught_up/1)
      {:ok, settings}
    end)
  end
end
