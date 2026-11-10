defmodule Basa.Payments.Changes.PrepareCommission do
  use Ash.Resource.Change
  alias Basa.I18n

  @impl true
  def change(changeset, _opts, context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      booking_id = Ash.Changeset.get_argument(changeset, :booking_id)
      amount = Ash.Changeset.get_argument(changeset, :amount)

      case Ash.get(Basa.Bookings.Booking, booking_id, authorize?: false) do
        {:ok, %{owner_id: owner, status: :completed} = b} when owner == context.actor.id ->
          cond do
            not Basa.Payments.Products.card_currency?(b.currency) ->
              Ash.Changeset.add_error(changeset,
                field: :amount,
                message: I18n.t("card payments are available in UAH, USD and EUR")
              )

            Decimal.compare(amount, b.price_amount) == :gt ->
              Ash.Changeset.add_error(changeset,
                field: :amount,
                message: I18n.t("can't be more than the booking")
              )

            true ->
              Ash.Changeset.force_change_attributes(changeset, %{
                purpose: :commission,
                booking_id: b.id,
                amount: amount,
                currency: b.currency
              })
          end

        _ ->
          Ash.Changeset.add_error(changeset,
            field: :booking_id,
            message: I18n.t("is not available")
          )
      end
    end)
  end
end
