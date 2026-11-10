defmodule Basa.Payments.Changes.OpenCheckout do
  use Ash.Resource.Change
  use Gettext, backend: BasaWeb.Gettext

  @impl true
  def change(changeset, _opts, context) do
    changeset
    |> Ash.Changeset.before_action(fn changeset ->
      if changeset.valid? do
        id = Ash.Changeset.get_attribute(changeset, :id)

        params = %{
          reference: id,
          amount: Ash.Changeset.get_attribute(changeset, :amount),
          currency: Ash.Changeset.get_attribute(changeset, :currency),
          description: description(changeset),
          customer_id: "basa_" <> context.actor.id,
          return_url: BasaWeb.Endpoint.url() <> "/payments/#{id}/return"
        }

        checkout =
          if Basa.Payments.enabled?(),
            do: Basa.Payments.Gateway.create_checkout(params),
            else: {:error, :switched_off}

        case checkout do
          {:ok, checkout} ->
            Ash.Changeset.force_change_attributes(changeset, Map.put(checkout, :status, :pending))

          {:error, _reason} ->
            Ash.Changeset.add_error(changeset,
              field: :amount,
              message: Basa.I18n.t("payments are unavailable right now, please try later")
            )
        end
      else
        changeset
      end
    end)
    |> Ash.Changeset.after_transaction(fn
      _cs, {:ok, payment} ->
        Basa.Payments.ReconcileWorker.schedule(payment.id)
        {:ok, payment}

      _cs, other ->
        other
    end)
  end

  defp description(changeset) do
    case Ash.Changeset.get_attribute(changeset, :purpose) do
      :commission -> gettext("BASA commission")
      :premium -> Basa.Payments.Products.label(Ash.Changeset.get_attribute(changeset, :product))
    end
  end
end
