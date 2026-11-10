defmodule Basa.Catalog.Validations.OwnsBasketAndRoom do
  use Ash.Resource.Validation

  @impl true
  def validate(changeset, _opts, context) do
    owner_id =
      Ash.Changeset.get_attribute(changeset, :owner_id) || (context.actor && context.actor.id)

    with :ok <-
           owned(
             Basa.Catalog.OfferBasket,
             Ash.Changeset.get_attribute(changeset, :basket_id),
             owner_id,
             :basket_id
           ) do
      owned(
        Basa.Catalog.Room,
        Ash.Changeset.get_attribute(changeset, :room_id),
        owner_id,
        :room_id
      )
    end
  end

  defp owned(_resource, nil, _owner_id, _field), do: :ok

  defp owned(resource, id, owner_id, field) do
    case Ash.get(resource, id, authorize?: false) do
      {:ok, %{owner_id: ^owner_id}} -> :ok
      _ -> {:error, field: field, message: Basa.I18n.t("must be one of your own")}
    end
  end
end
