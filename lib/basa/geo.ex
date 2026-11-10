defmodule Basa.Geo do
  use Ash.Domain, otp_app: :basa

  require Ash.Query
  require Ash.Sort
  alias Basa.Geo.{City, Demand, Index, Photon}

  resources do
    resource City do
      define :get_city, action: :read, get_by: [:id]
    end

    resource Demand do
      define :list_demand, action: :read
      define :resolve_demand, action: :resolve, args: [:status]
    end
  end

  def suggest(q, opts \\ []) do
    q = String.trim(q || "")
    limit = opts[:limit] || 8

    cond do
      q == "" ->
        popular(limit)

      true ->
        case Index.city_ids(q, limit: limit, country_code: opts[:country_code]) do
          ids when is_list(ids) -> by_ids(ids)
          :unavailable -> pg_search(q, limit, opts[:country_code])
        end
    end
  end

  def popular(limit \\ 8) do
    City
    |> Ash.Query.sort(picks: :desc, population: :desc)
    |> Ash.Query.limit(limit)
    |> Ash.read!(authorize?: false)
  end

  def nearest(lat, lng, opts \\ []) do
    City
    |> then(fn q ->
      if c = opts[:country_code], do: Ash.Query.filter(q, country_code == ^c), else: q
    end)
    |> Ash.Query.sort(
      Ash.Sort.expr_sort(
        fragment(
          "ST_SetSRID(ST_MakePoint(?, ?), 4326)::geography <-> ST_SetSRID(ST_MakePoint(?, ?), 4326)::geography",
          lng,
          lat,
          ^lng,
          ^lat
        ),
        :float
      )
    )
    |> Ash.Query.limit(1)
    |> Ash.read_one!(authorize?: false)
  end

  def get(nil), do: nil

  def get(id) do
    case Ash.get(City, id, authorize?: false) do
      {:ok, city} -> city
      _ -> nil
    end
  end

  def find_by_name(name) when is_binary(name) do
    name = name |> String.trim() |> String.downcase()

    City
    |> Ash.Query.filter(
      fragment("lower(?)", name) == ^name or fragment("lower(?)", ascii_name) == ^name or
        fragment(
          "EXISTS (SELECT 1 FROM jsonb_each_text(?) v WHERE lower(v.value) = ?)",
          names,
          ^name
        )
    )
    |> Ash.Query.sort(picks: :desc, population: :desc)
    |> Ash.Query.limit(1)
    |> Ash.read_one!(authorize?: false)
  end

  def find_by_name(_), do: nil

  def picked(%City{} = city), do: Ash.update(city, %{}, action: :pick, authorize?: false)
  def picked(_), do: :ok

  def external(q, locale \\ "en") do
    case Photon.search(q, to_string(locale)) do
      {:ok, candidates} ->
        known = candidates |> Enum.map(& &1.id) |> by_ids() |> MapSet.new(& &1.id)

        candidates
        |> Enum.filter(&Basa.Geo.Countries.served?(&1.country_code))
        |> Enum.reject(&(MapSet.member?(known, &1.id) or have_nearby?(&1)))

      {:error, _} ->
        []
    end
  end

  def add_candidate(%{id: "osm:" <> _ = id} = cand, origin \\ :lessor) do
    if city = get(id) do
      {:ok, city}
    else
      details =
        case Photon.details(id) do
          {:ok, d} -> d
          {:error, _} -> %{names: %{}, population: nil, record: nil}
        end

      near =
        nearest(cand.lat, cand.lng, country_code: cand.country_code) ||
          nearest(cand.lat, cand.lng)

      City
      |> Ash.Changeset.for_create(
        :add,
        %{
          id: id,
          source: :osm,
          origin: origin,
          name: cand.name,
          names: Map.merge(%{"en" => cand.name}, details.names),
          ascii_name: cand.name,
          country_code: cand.country_code || (near && near.country_code) || "XX",
          admin1: cand.admin1,
          lat: cand.lat,
          lng: cand.lng,
          timezone: (near && near.timezone) || "Etc/UTC",
          population: details.population || 0,
          raw: %{"photon" => cand.feature, "nominatim" => details.record}
        },
        authorize?: false
      )
      |> Ash.create()
    end
  end

  def record_miss(q, locale \\ "en") do
    q = String.trim(q || "")

    if String.length(q) >= 3 do
      attrs =
        case Photon.search(q, to_string(locale)) do
          {:ok, [top | _]} ->
            %{
              id: top.id,
              label:
                Enum.join(Enum.reject([top.name, top.admin1, top.country_code], &is_nil/1), ", "),
              country_code: top.country_code,
              candidate: top
            }

          _ ->
            %{id: "q:" <> String.downcase(q), label: q}
        end

      Demand
      |> Ash.Changeset.for_create(:record, Map.put(attrs, :query, q), authorize?: false)
      |> Ash.create()
    else
      :ok
    end
  end

  def add_wanted(%Demand{candidate: %{} = cand} = demand, actor) do
    cand = for {k, v} <- cand, into: %{}, do: {String.to_existing_atom(to_string(k)), v}

    with {:ok, city} <- add_candidate(cand, :admin),
         {:ok, _} <- resolve_demand(demand, :added, actor: actor) do
      {:ok, city}
    end
  end

  def add_wanted(_demand, _actor), do: {:error, :no_candidate}

  defp have_nearby?(%{lat: lat, lng: lng, name: name}) do
    name = String.downcase(name)

    City
    |> Ash.Query.filter(
      fragment(
        "ST_DWithin(ST_SetSRID(ST_MakePoint(?, ?), 4326)::geography, ST_SetSRID(ST_MakePoint(?, ?), 4326)::geography, 15000)",
        lng,
        lat,
        ^lng,
        ^lat
      ) and
        (fragment("lower(?)", name) == ^name or fragment("lower(?)", ascii_name) == ^name or
           fragment(
             "EXISTS (SELECT 1 FROM jsonb_each_text(?) v WHERE lower(v.value) = ?)",
             names,
             ^name
           ))
    )
    |> Ash.exists?(authorize?: false)
  end

  defp by_ids([]), do: []

  defp by_ids(ids) do
    found =
      City
      |> Ash.Query.filter(id in ^ids)
      |> Ash.read!(authorize?: false)
      |> Map.new(&{&1.id, &1})

    ids |> Enum.map(&found[&1]) |> Enum.reject(&is_nil/1)
  end

  defp pg_search(q, limit, country_code) do
    pattern = String.downcase(q) <> "%"

    City
    |> Ash.Query.filter(
      fragment("lower(?) LIKE ?", name, ^pattern) or
        fragment("lower(?) LIKE ?", ascii_name, ^pattern) or
        fragment(
          "EXISTS (SELECT 1 FROM jsonb_each_text(?) v WHERE lower(v.value) LIKE ?)",
          names,
          ^pattern
        )
    )
    |> then(&if(country_code, do: Ash.Query.filter(&1, country_code == ^country_code), else: &1))
    |> Ash.Query.sort(picks: :desc, population: :desc)
    |> Ash.Query.limit(limit)
    |> Ash.read!(authorize?: false)
  end
end
