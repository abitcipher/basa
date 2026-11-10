defmodule Basa.Import.Price do
  @currencies [
    {"грн", "UAH"},
    {"₴", "UAH"},
    {"uah", "UAH"},
    {"€", "EUR"},
    {"eur", "EUR"},
    {"$", "USD"},
    {"usd", "USD"},
    {"zł", "PLN"},
    {"pln", "PLN"},
    {"lei", "RON"},
    {"ron", "RON"},
    {"₺", "TRY"},
    {"tl", "TRY"},
    {"try", "TRY"},
    {"£", "GBP"},
    {"gbp", "GBP"},
    {"chf", "CHF"},
    {"czk", "CZK"},
    {"kč", "CZK"}
  ]

  @spec amount(String.t() | number() | nil) :: Decimal.t() | nil
  def amount(nil), do: nil
  def amount(n) when is_integer(n), do: Decimal.new(n)
  def amount(n) when is_float(n), do: Decimal.from_float(n)

  def amount(text) when is_binary(text) do
    case Regex.run(~r/\d[\d\s\x{00A0}\x{202F}'.,]*/u, text) do
      [raw] -> raw |> normalize() |> to_decimal()
      _ -> nil
    end
  end

  @spec currency(String.t() | nil) :: String.t() | nil
  def currency(nil), do: nil

  def currency(text) do
    down = String.downcase(text)

    Regex.run(~r/\b([A-Z]{3})\b/, text) |> iso() ||
      Enum.find_value(@currencies, fn {sign, code} -> if word?(down, sign), do: code end)
  end

  defp iso([_, code]) when code in ~w(UAH EUR USD PLN RON TRY GBP CHF CZK), do: code
  defp iso(_), do: nil

  defp word?(text, sign) do
    if sign =~ ~r/^\p{L}+$/u,
      do: Regex.match?(~r/(^|[^\p{L}])#{Regex.escape(sign)}($|[^\p{L}])/u, text),
      else: String.contains?(text, sign)
  end

  defp normalize(raw) do
    digits =
      raw
      |> String.replace(~r/[\s\x{00A0}\x{202F}']/u, "")
      |> String.trim_trailing(".")
      |> String.trim_trailing(",")

    case {last(digits, "."), last(digits, ",")} do
      {nil, nil} ->
        digits

      {d, c} when is_integer(d) and is_integer(c) and d > c ->
        String.replace(digits, ",", "")

      {d, c} when is_integer(d) and is_integer(c) ->
        digits |> String.replace(".", "") |> String.replace(",", ".")

      {nil, _} ->
        one_separator(digits, ",")

      {_, nil} ->
        one_separator(digits, ".")
    end
  end

  defp one_separator(digits, sep) do
    parts = String.split(digits, sep)

    case parts do
      [whole, frac] when byte_size(frac) in [1, 2] -> whole <> "." <> frac
      _ -> Enum.join(parts)
    end
  end

  defp last(text, sep) do
    case :binary.matches(text, sep) do
      [] -> nil
      matches -> matches |> List.last() |> elem(0)
    end
  end

  defp to_decimal(""), do: nil

  defp to_decimal(text) do
    case Decimal.parse(text) do
      {d, ""} -> d
      _ -> nil
    end
  end
end
