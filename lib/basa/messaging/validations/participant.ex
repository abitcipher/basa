defmodule Basa.Messaging.Validations.Participant do
  use Ash.Resource.Validation

  @impl true
  def validate(changeset, _opts, context) do
    id = Ash.Changeset.get_attribute(changeset, :conversation_id)
    actor_id = context.actor && context.actor.id

    case id && Ash.get(Basa.Messaging.Conversation, id, authorize?: false) do
      {:ok, %{lessor_id: ^actor_id}} -> :ok
      {:ok, %{lessee_id: ^actor_id}} -> :ok
      _ -> {:error, field: :conversation_id, message: Basa.I18n.t("is not yours")}
    end
  end
end
