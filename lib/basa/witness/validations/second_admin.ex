defmodule Basa.Witness.Validations.SecondAdmin do
  use Ash.Resource.Validation

  @impl true
  def validate(changeset, _opts, context) do
    actor = context.actor

    if actor && actor.id != changeset.data.filed_by_id,
      do: :ok,
      else: {:error, field: :status, message: "a second admin must decide"}
  end
end
