defmodule Basa.Catalog.Changes.ValidateAttrs do
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      category_id = Ash.Changeset.get_attribute(changeset, :category_id)
      attrs = Ash.Changeset.get_attribute(changeset, :attrs) || %{}

      with id when not is_nil(id) <- category_id,
           {:ok, category} <- Ash.get(Basa.Catalog.Category, id, authorize?: false),
           {:ok, attrs} <- Basa.JsonSchema.validate(category.attr_schema, attrs) do
        Ash.Changeset.force_change_attribute(changeset, :attrs, attrs)
      else
        nil ->
          changeset

        {:error, messages} when is_list(messages) ->
          Enum.reduce(messages, changeset, fn message, acc ->
            Ash.Changeset.add_error(acc, field: :attrs, message: message)
          end)

        {:error, error} ->
          Ash.Changeset.add_error(changeset, error)
      end
    end)
  end
end
