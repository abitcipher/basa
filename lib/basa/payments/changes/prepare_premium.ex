defmodule Basa.Payments.Changes.PreparePremium do
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      lot_id = Ash.Changeset.get_argument(changeset, :lot_id)
      product = Ash.Changeset.get_argument(changeset, :product)

      case Ash.get(Basa.Catalog.Lot, lot_id, authorize?: false) do
        {:ok, %{owner_id: owner, state: state} = lot}
        when owner == context.actor.id and state != :archived ->
          {amount, currency} = Basa.Payments.Products.price(product, lot.currency)

          Ash.Changeset.force_change_attributes(changeset, %{
            purpose: :premium,
            product: product,
            lot_id: lot.id,
            amount: amount,
            currency: currency
          })

        _ ->
          Ash.Changeset.add_error(changeset,
            field: :lot_id,
            message: Basa.I18n.t("is not available")
          )
      end
    end)
  end
end
