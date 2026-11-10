defmodule Basa.Geo.Countries do
  @path Path.join([__DIR__, "../../../priv/geo/countries.json"])
  @external_resource @path

  @countries @path
             |> File.read!()
             |> Jason.decode!()
             |> Map.new(&{&1["code"], &1})

  @supported ~w(UAH USD EUR)

  @excluded ~w(RU BY)

  def excluded, do: @excluded

  def served?(code), do: is_binary(code) and String.upcase(code) not in @excluded

  def get(code), do: Map.get(@countries, code && String.upcase(code))

  def name(code, locale \\ "en") do
    case get(code) do
      nil -> code
      c -> c["names"][to_string(locale)] || c["name"]
    end
  end

  def currency(code) do
    case get(code) do
      %{"currency" => cur} when cur in @supported -> String.to_existing_atom(cur)
      %{"continent" => "EU"} -> :EUR
      _ -> :USD
    end
  end
end
