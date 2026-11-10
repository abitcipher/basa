defmodule Mix.Tasks.Basa.Geo.BuildSeed do
  @shortdoc "Builds priv/geo seed files (cities, countries) from GeoNames"
  use Mix.Task

  @dump "https://download.geonames.org/export/dump"
  @langs Basa.I18n.codes()
  @name_countries ~w(TR)

  @feature_codes ~w(PPL PPLA PPLA2 PPLA3 PPLA4 PPLC PPLG)

  @city_columns ~w(geonameid name asciiname alternatenames latitude longitude feature_class
                   feature_code country_code cc2 admin1_code admin2_code admin3_code admin4_code
                   population elevation dem timezone modification_date)

  @impl true
  def run(args) do
    {opts, _, _} =
      OptionParser.parse(args, strict: [min_population: :integer, countries: :string])

    Application.ensure_all_started(:req)
    min_population = opts[:min_population] || 100_000
    tmp = Path.join(System.tmp_dir!(), "basa-geonames-#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)

    try do
      countries = countries(tmp)

      codes =
        case opts[:countries] do
          nil ->
            for {code, c} <- countries,
                c.continent == "EU",
                code not in Basa.Geo.Countries.excluded(),
                do: code

          list ->
            String.split(list, ",", trim: true) |> Enum.map(&String.upcase/1)
        end
        |> Enum.sort()

      admin1 = admin1(tmp)

      cities =
        tmp
        |> cities()
        |> Enum.filter(
          &(&1["country_code"] in codes and &1["feature_code"] in @feature_codes and
              String.to_integer(&1["population"]) > min_population)
        )

      Mix.shell().info("#{length(cities)} cities in #{length(codes)} countries")

      wanted =
        MapSet.new(
          Enum.map(cities, & &1["geonameid"]) ++
            Enum.map(countries, fn {_, c} -> c.geonameid end)
        )

      country_ids = MapSet.new(countries, fn {_, c} -> c.geonameid end)

      names =
        (codes ++ @name_countries)
        |> Enum.uniq()
        |> Enum.reduce(%{}, &Map.merge(&2, alternate_names(tmp, &1, wanted, country_ids)))

      countries_out =
        countries
        |> Enum.map(fn {code, c} ->
          %{
            code: code,
            name: c.name,
            names: localized(names[c.geonameid], c.name),
            continent: c.continent,
            currency: c.currency,
            geonameid: c.geonameid
          }
        end)
        |> Enum.sort_by(& &1.code)

      cities_out =
        cities
        |> Enum.map(fn row ->
          %{
            id: "gn:" <> row["geonameid"],
            source: "geonames",
            name: row["name"],
            names: localized(names[row["geonameid"]], row["name"]),
            ascii_name: row["asciiname"],
            country_code: row["country_code"],
            admin1: admin1["#{row["country_code"]}.#{row["admin1_code"]}"],
            lat: number(row["latitude"]),
            lng: number(row["longitude"]),
            timezone: row["timezone"],
            population: String.to_integer(row["population"]),
            raw: Map.drop(row, ["alternatenames"])
          }
        end)
        |> Enum.sort_by(&{&1.country_code, -&1.population})

      File.mkdir_p!("priv/geo")
      File.write!("priv/geo/countries.json", Jason.encode_to_iodata!(countries_out, pretty: true))

      File.write!(
        "priv/geo/cities.json.gz",
        :zlib.gzip(Jason.encode_to_iodata!(cities_out))
      )

      Mix.shell().info(
        "Wrote priv/geo/countries.json (#{length(countries_out)}) and priv/geo/cities.json.gz (#{length(cities_out)})"
      )
    after
      File.rm_rf!(tmp)
    end
  end

  defp countries(tmp) do
    tmp
    |> download("countryInfo.txt")
    |> File.stream!()
    |> Stream.reject(&String.starts_with?(&1, "#"))
    |> Stream.map(&(&1 |> String.trim_trailing("\n") |> String.split("\t")))
    |> Enum.flat_map(fn
      [code, _iso3, _num, _fips, name, _cap, _area, _pop, continent, _tld, currency | rest] ->
        [
          {code,
           %{name: name, continent: continent, currency: currency, geonameid: Enum.at(rest, 5)}}
        ]

      _ ->
        []
    end)
    |> Map.new()
  end

  defp admin1(tmp) do
    tmp
    |> download("admin1CodesASCII.txt")
    |> File.stream!()
    |> Stream.map(&String.split(String.trim_trailing(&1, "\n"), "\t"))
    |> Map.new(fn [code, name | _] -> {code, name} end)
  end

  defp cities(tmp) do
    tmp
    |> download("cities15000.zip")
    |> unzip("cities15000.txt")
    |> String.split("\n", trim: true)
    |> Enum.map(&Map.new(Enum.zip(@city_columns, String.split(&1, "\t"))))
  end

  defp alternate_names(tmp, country, wanted, country_ids) do
    tmp
    |> download("alternatenames/#{country}.zip")
    |> unzip("#{country}.txt")
    |> String.split("\n", trim: true)
    |> Enum.reduce(%{}, fn line, acc ->
      case String.split(line, "\t") do
        [_id, gid, lang, name, preferred, short, colloquial, historic | _]
        when lang in @langs and colloquial != "1" and historic != "1" ->
          if MapSet.member?(wanted, gid) and (lang == "uk" or not cyrillic?(name)) and
               not abbreviation?(name) do
            rank =
              if MapSet.member?(country_ids, gid),
                do: if(short == "1", do: 0, else: 2) + if(preferred == "1", do: 0, else: 1),
                else: if(preferred == "1", do: 0, else: 2) + if(short == "1", do: 1, else: 0)

            Map.update(acc, gid, %{lang => {rank, name}}, fn names ->
              Map.update(names, lang, {rank, name}, fn {r, _} = old ->
                if rank < r, do: {rank, name}, else: old
              end)
            end)
          else
            acc
          end

        _ ->
          acc
      end
    end)
  rescue
    e in [MatchError, Req.TransportError] ->
      Mix.shell().info("no alternate names for #{country}: #{Exception.message(e)}")
      %{}
  end

  defp cyrillic?(name), do: String.match?(name, ~r/\p{Cyrillic}/u)

  defp abbreviation?(name), do: String.match?(name, ~r/^[A-Z]{2,4}$/)

  defp localized(nil, fallback), do: Map.new(@langs, &{&1, fallback})

  defp localized(names, fallback) do
    en = with {_, n} <- names["en"], do: n

    Map.new(@langs, fn lang ->
      {lang,
       case names[lang] do
         {_, name} -> name
         nil -> en || fallback
       end}
    end)
  end

  defp number(text), do: text |> Float.parse() |> elem(0)

  defp download(tmp, file) do
    path = Path.join(tmp, String.replace(file, "/", "_"))

    unless File.exists?(path) do
      Mix.shell().info("download #{file}")
      %{status: 200} = Req.get!("#{@dump}/#{file}", into: File.stream!(path), retry: :transient)
    end

    path
  end

  defp unzip(zip, member) do
    {:ok, [{_, data}]} =
      :zip.extract(String.to_charlist(zip), [:memory, file_list: [String.to_charlist(member)]])

    data
  end
end
