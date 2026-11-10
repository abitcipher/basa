defmodule Basa.Money do
  @currencies [:UAH, :USD, :EUR, :USDT, :GRAM]

  def currencies, do: @currencies

  def format(nil, _currency), do: "—"

  def format(%Decimal{} = amount, currency) do
    "#{amount |> Decimal.round(2) |> Decimal.to_string(:normal)} #{currency}"
  end

  def suggested_daily_rate(%Decimal{} = value, percent \\ 3) do
    value |> Decimal.mult(percent) |> Decimal.div(100) |> Decimal.round(0, :up)
  end
end
