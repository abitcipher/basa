defmodule Basa.Payments.Products do
  use Gettext, backend: BasaWeb.Gettext

  @card_currencies [:UAH, :USD, :EUR]

  @products %{
    featured_7d: %{days: 7, prices: %{UAH: 199, USD: 5, EUR: 5}},
    featured_30d: %{days: 30, prices: %{UAH: 599, USD: 15, EUR: 15}}
  }

  def card_currencies, do: @card_currencies
  def card_currency?(c), do: c in @card_currencies
  def products, do: [:featured_7d, :featured_30d]
  def get(product), do: Map.fetch!(@products, product)

  def price(product, currency) do
    currency = if card_currency?(currency), do: currency, else: :UAH
    {Decimal.new(get(product).prices[currency]), currency}
  end

  def label(:featured_7d), do: gettext("Featured for 7 days")
  def label(:featured_30d), do: gettext("Featured for 30 days")

  def suggested_commission(%Decimal{} = price) do
    price |> Decimal.mult(5) |> Decimal.div(100) |> Decimal.round(0, :up) |> Decimal.max(1)
  end
end
