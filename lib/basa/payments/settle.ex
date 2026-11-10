defmodule Basa.Payments.Settle do
  require Ash.Query
  alias Basa.Payments.{Gateway, Payment}

  def refresh(%Payment{provider_payment_id: id} = payment) when is_binary(id) do
    with {:ok, status} <- Gateway.fetch_status(id), do: apply_status(payment, status)
  end

  def refresh(payment), do: {:ok, payment}

  def by_provider_id(provider_id) do
    Payment
    |> Ash.Query.filter(provider_payment_id == ^provider_id)
    |> Ash.read_one(authorize?: false)
  end

  def apply_status(%Payment{status: same} = payment, same), do: {:ok, payment}

  def apply_status(%Payment{status: final} = payment, _)
      when final in [:succeeded, :failed, :cancelled, :expired],
      do: {:ok, payment}

  def apply_status(%Payment{} = payment, status) do
    Basa.Repo.transaction(fn ->
      updated =
        payment
        |> Ash.Changeset.for_update(:settle, %{status: status}, authorize?: false)
        |> Ash.update!(authorize?: false)

      if status == :succeeded, do: apply_effect(updated)
      updated
    end)
    |> tap(fn
      {:ok, %{status: :succeeded} = p} ->
        Basa.Events.External.publish("payment.succeeded", %{
          payment_id: p.id,
          purpose: p.purpose,
          product: p.product,
          amount: Decimal.to_string(p.amount),
          currency: p.currency,
          booking_id: p.booking_id,
          lot_id: p.lot_id
        })

        Basa.Events.notify_user(p.user_id, {:payment_settled, p.id})

      {:ok, p} ->
        Basa.Events.notify_user(p.user_id, {:payment_settled, p.id})

      _ ->
        :ok
    end)
  end

  defp apply_effect(%Payment{purpose: :premium, product: product, lot_id: lot_id})
       when not is_nil(lot_id) do
    days = Basa.Payments.Products.get(product).days
    lot = Ash.get!(Basa.Catalog.Lot, lot_id, authorize?: false)

    from =
      if lot.featured_until && DateTime.after?(lot.featured_until, DateTime.utc_now()),
        do: lot.featured_until,
        else: DateTime.utc_now()

    lot
    |> Ash.Changeset.for_update(
      :feature,
      %{featured_until: DateTime.add(from, days * 86_400, :second)},
      authorize?: false
    )
    |> Ash.update!(authorize?: false)
  end

  defp apply_effect(_payment), do: :ok
end
