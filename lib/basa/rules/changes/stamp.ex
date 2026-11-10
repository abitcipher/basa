defmodule Basa.Rules.Changes.Stamp do
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, %{actor: actor}),
    do: Ash.Changeset.force_change_attribute(changeset, :updated_by_email, who(actor))

  defp who(nil), do: nil
  defp who(%{email: email}) when not is_nil(email), do: to_string(email)
  defp who(actor), do: Map.get(actor, :display_name)
end
