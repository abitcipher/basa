defmodule Basa.Import.Detect do
  alias Basa.Import.Price

  @fields ~w(name description price currency photos brand model sku category address area rooms url)a
  @max_photos 30
  @max_state_bytes 2_000_000

  @type source :: :json_ld | :microdata | :specs | :gallery | :state | :meta | :html
  @type result :: %{
          fields: %{optional(atom()) => term()},
          sources: %{optional(atom()) => source()},
          specs: [{String.t(), String.t()}],
          json_ld: [map()],
          states: [%{name: String.t(), data: term()}]
        }

  @product_types ~w(Product IndividualProduct ProductModel ProductGroup Car Vehicle Motorcycle)
  @place_types ~w(RealEstateListing Accommodation House Apartment SingleFamilyResidence Residence
                  Room Suite HotelRoom LodgingBusiness Hotel Hostel VacationRental Place Offer)

  @spec page(String.t(), String.t()) :: result()
  def page(html, base_url) do
    doc = Floki.parse_document!(html)
    nodes = json_ld_nodes(doc)
    states = states(doc)
    specs = Enum.uniq_by(specs(doc) ++ state_specs(states), &String.downcase(elem(&1, 0)))

    found = [
      json_ld: from_json_ld(nodes),
      microdata: from_microdata(doc),
      specs: from_specs(specs),
      gallery: linked_images(doc),
      state: %{address: state_address(states)},
      meta: from_meta(doc),
      html: from_html(doc)
    ]

    {fields, sources} = merge(found, base_url)

    {fields, sources} =
      if fields[:url],
        do: {fields, sources},
        else: {Map.put(fields, :url, base_url), Map.put(sources, :url, :html)}

    %{fields: fields, sources: sources, specs: specs, json_ld: nodes, states: states}
  end

  defp merge(found, base) do
    Enum.reduce(@fields, {%{}, %{}}, fn
      :photos, acc ->
        thumbs =
          found
          |> Enum.flat_map(fn {_, f} -> List.wrap(f[:thumbs]) end)
          |> Enum.map(&absolute(&1, base))
          |> MapSet.new()

        photos =
          found
          |> Enum.flat_map(fn {_, f} -> List.wrap(f[:photos]) end)
          |> Enum.map(&absolute(&1, base))
          |> Enum.reject(&(is_nil(&1) or MapSet.member?(thumbs, &1)))
          |> Enum.uniq()
          |> largest_sizes()
          |> Enum.take(@max_photos)

        source = Enum.find_value(found, fn {s, f} -> if List.wrap(f[:photos]) != [], do: s end)
        put(acc, :photos, if(photos != [], do: photos), source)

      field, acc ->
        case Enum.find(found, fn {_, f} -> present?(f[field]) end) do
          {source, f} -> put(acc, field, clean(field, f[field], base), source)
          nil -> acc
        end
    end)
  end

  defp put(acc, _field, nil, _source), do: acc

  defp put({fields, sources}, field, value, source),
    do: {Map.put(fields, field, value), Map.put(sources, field, source)}

  defp present?(nil), do: false
  defp present?(""), do: false
  defp present?([]), do: false
  defp present?(_), do: true

  def clean_field(:photos, values, base),
    do:
      values
      |> List.wrap()
      |> Enum.map(&absolute(&1, base))
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

  def clean_field(field, value, base), do: clean(field, value, base)

  def fields, do: @fields

  defp clean(:price, value, _), do: Price.amount(value)
  defp clean(:url, value, base), do: absolute(value, base)
  defp clean(:description, value, _), do: value |> text() |> String.slice(0, 5000)
  defp clean(_field, value, _) when is_binary(value), do: text(value)
  defp clean(_field, value, _), do: value

  @doc false
  def text(value) do
    value =
      if value =~ ~r/[<&]/,
        do: value |> Floki.parse_fragment!() |> Floki.text(sep: " "),
        else: value

    value |> String.replace(~r/\s+/u, " ") |> String.trim()
  end

  defp absolute(nil, _), do: nil

  defp absolute(url, base) when is_binary(url) do
    url = String.trim(url)

    cond do
      url == "" or String.starts_with?(url, "data:") -> nil
      true -> base |> URI.merge(url) |> URI.to_string()
    end
  rescue
    _ -> nil
  end

  defp absolute(_, _), do: nil

  defp json_ld_nodes(doc) do
    doc
    |> Floki.find(~s(script[type="application/ld+json"]))
    |> Enum.flat_map(fn {_, _, children} ->
      json = children |> Enum.join() |> String.replace(~r/^\s*<!--|-->\s*$/, "")

      case Jason.decode(json) do
        {:ok, data} -> flatten(data)
        _ -> []
      end
    end)
  end

  defp flatten(list) when is_list(list), do: Enum.flat_map(list, &flatten/1)
  defp flatten(%{"@graph" => graph}), do: flatten(graph)
  defp flatten(%{} = node), do: [node]
  defp flatten(_), do: []

  defp from_json_ld(nodes) do
    main =
      Enum.find(nodes, &type?(&1, @product_types)) ||
        Enum.find(nodes, &type?(&1, @place_types))

    case main do
      nil ->
        %{}

      node ->
        inner =
          Enum.find([node["mainEntity"], node["about"], node["itemOffered"]], &is_map/1) || %{}

        f =
          Map.merge(node_fields(inner), node_fields(node), fn _, a, b ->
            if present?(b), do: b, else: a
          end)

        Map.put_new(f, :category, breadcrumb_category(nodes, f[:name]))
    end
  end

  defp type?(node, types),
    do: node |> Map.get("@type") |> List.wrap() |> Enum.any?(&(&1 in types))

  defp node_fields(node) do
    offer = offer(node["offers"]) || if(type?(node, ["Offer"]), do: node, else: %{})

    %{
      name: str(node["name"]),
      description: str(node["description"]),
      photos: images(node["image"]) ++ images(node["photo"]),
      brand: name_of(node["brand"]) || name_of(node["manufacturer"]),
      model: name_of(node["model"]) || str(node["mpn"]),
      sku: str(node["sku"]),
      category: category(node["category"]),
      price: price(offer),
      currency:
        str(offer["priceCurrency"]) || str(get_in(offer, ["priceSpecification", "priceCurrency"])),
      address: address(node["address"]),
      area: area(node["floorSize"]),
      rooms: str(node["numberOfRooms"]) || str(node["numberOfBedrooms"]),
      url: str(node["url"])
    }
  end

  defp offer(list) when is_list(list), do: list |> Enum.map(&offer/1) |> Enum.find(& &1)
  defp offer(%{} = offer), do: offer
  defp offer(_), do: nil

  defp price(offer) do
    Enum.find_value(
      [offer["price"], offer["lowPrice"], get_in(offer, ["priceSpecification", "price"])],
      fn
        nil -> nil
        p -> to_string(p)
      end
    )
  end

  defp images(nil), do: []
  defp images(list) when is_list(list), do: Enum.flat_map(list, &images/1)
  defp images(url) when is_binary(url), do: [url]
  defp images(%{} = img), do: images(img["contentUrl"] || img["url"])
  defp images(_), do: []

  defp name_of(%{"name" => name}), do: str(name)
  defp name_of(other), do: str(other)

  defp category(list) when is_list(list),
    do: list |> Enum.map(&category/1) |> Enum.reject(&is_nil/1) |> List.last()

  defp category(%{"name" => name}), do: str(name)

  defp category("http" <> _ = url),
    do:
      url
      |> URI.parse()
      |> Map.get(:path, "")
      |> to_string()
      |> String.split("/", trim: true)
      |> List.last()
      |> str()

  defp category(other), do: str(other)

  defp address(%{} = a),
    do:
      [a["streetAddress"], a["addressLocality"], a["addressRegion"], name_of(a["addressCountry"])]
      |> Enum.map(&str/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Enum.join(", ")
      |> case(
        do: (
          "" -> nil
          s -> s
        )
      )

  defp address(other), do: str(other)

  defp area(%{"value" => v} = size),
    do:
      [str(v), str(size["unitText"]) || str(size["unitCode"])]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(" ")

  defp area(other), do: str(other)

  defp breadcrumb_category(nodes, name) do
    nodes
    |> Enum.find(&type?(&1, ["BreadcrumbList"]))
    |> case do
      %{"itemListElement" => items} when is_list(items) ->
        items
        |> Enum.sort_by(&(&1["position"] || 0))
        |> Enum.map(&(str(&1["name"]) || name_of(&1["item"])))
        |> Enum.reject(&(is_nil(&1) or &1 == name))
        |> List.last()

      _ ->
        nil
    end
  end

  defp str(nil), do: nil
  defp str(s) when is_binary(s), do: if(String.trim(s) == "", do: nil, else: String.trim(s))
  defp str(n) when is_number(n), do: to_string(n)
  defp str(_), do: nil

  defp from_microdata(doc) do
    case Floki.find(doc, ~s([itemscope][itemtype*="schema.org/Product"])) do
      [scope | _] ->
        scope = [scope]

        %{
          name: prop(scope, "name"),
          description: prop(scope, "description"),
          photos:
            scope
            |> Floki.find(~s([itemprop="image"]))
            |> Enum.map(&value/1)
            |> Enum.reject(&is_nil/1),
          brand: scoped_name(scope, "brand") || scoped_name(scope, "manufacturer"),
          model: prop(scope, "model") || prop(scope, "mpn"),
          sku: prop(scope, "sku"),
          category: prop(scope, "category"),
          price: prop(scope, "price") || prop(scope, "lowPrice"),
          currency: prop(scope, "priceCurrency")
        }

      [] ->
        %{}
    end
  end

  defp prop(scope, name) do
    case Floki.find(scope, ~s([itemprop="#{name}"])) do
      [el | _] -> value(el)
      [] -> nil
    end
  end

  defp scoped_name(scope, name) do
    case Floki.find(scope, ~s([itemprop="#{name}"])) do
      [{_, attrs, _} = el | _] ->
        if List.keymember?(attrs, "itemscope", 0),
          do: prop([el], "name") || value(el),
          else: value(el)

      [] ->
        nil
    end
  end

  defp value({tag, _, _} = el) do
    attr = fn name -> el |> Floki.attribute(name) |> List.first() |> str() end

    attr.("content") ||
      (tag in ~w(img source) && image_src(attr)) ||
      (tag in ~w(a link) && attr.("href")) ||
      el |> Floki.text(sep: " ") |> str()
  end

  @labels %{
    brand: ~w(виробник бренд марка производитель brand manufacturer maker hersteller marke marque
              fabricant marca fabricante produttore producent producător üretici),
    model: ~w(модель model modell modèle modelo modello),
    price: ~w(ціна цена вартість price preis prix precio prezzo cena preț pret fiyat),
    sku: [
      "артикул",
      "код товару",
      "код",
      "sku",
      "article",
      "art.-nr.",
      "artikelnummer",
      "référence",
      "referencia",
      "codice",
      "kod",
      "cod",
      "stok kodu"
    ],
    category: [
      "тип товару",
      "вид товару",
      "категорія товару",
      "категорія",
      "категория",
      "тип",
      "category",
      "product type",
      "kategorie",
      "produktart",
      "catégorie",
      "type de produit",
      "categoría",
      "tipo de producto",
      "categoria",
      "tipo di prodotto",
      "kategoria",
      "rodzaj produktu",
      "categorie",
      "tip produs",
      "kategori",
      "ürün tipi",
      "type"
    ],
    rooms: [
      "кількість кімнат",
      "кімнат",
      "кімнати",
      "rooms",
      "zimmer",
      "pièces",
      "habitaciones",
      "locali",
      "pokoje",
      "camere",
      "oda sayısı"
    ],
    area: [
      "загальна площа",
      "площа",
      "area",
      "fläche",
      "wohnfläche",
      "surface",
      "superficie",
      "powierzchnia",
      "suprafață",
      "alan"
    ],
    address: ~w(адреса адрес address adresse dirección indirizzo adres adresă)
  }

  def specs(doc) do
    rows =
      doc
      |> Floki.find("tr")
      |> Enum.flat_map(fn {_, _, children} ->
        case Enum.filter(children, &match?({tag, _, _} when tag in ["td", "th"], &1)) do
          [label, value] -> pair(label, value)
          _ -> []
        end
      end)

    dls =
      doc
      |> Floki.find("dl")
      |> Enum.flat_map(fn {_, _, children} ->
        children
        |> Enum.filter(&match?({tag, _, _} when tag in ["dt", "dd"], &1))
        |> Enum.chunk_every(2)
        |> Enum.flat_map(fn
          [{"dt", _, _} = dt, {"dd", _, _} = dd] -> pair(dt, dd)
          _ -> []
        end)
      end)

    Enum.uniq_by(rows ++ dls, &elem(&1, 0))
  end

  defp pair(label_el, value_el) do
    nested? = Floki.find([label_el, value_el], "table, tr") != []

    label =
      label_el |> Floki.text(sep: " ") |> text() |> String.trim_trailing(":") |> String.trim()

    value =
      value_el
      |> Floki.text(sep: "\n")
      |> String.split("\n")
      |> Enum.map(&text/1)
      |> Enum.reject(&(&1 == ""))

    if not nested? and label != "" and String.length(label) <= 40 and value != [] and
         String.length(Enum.join(value, " ")) <= 300,
       do: [{label, Enum.join(value, "\n")}],
       else: []
  end

  defp from_specs(specs) do
    lookup = Map.new(specs, fn {label, value} -> {String.downcase(label), value} end)

    fields =
      Map.new(@labels, fn {field, labels} ->
        {field, Enum.find_value(labels, &lookup[&1])}
      end)

    fields
    |> Map.new(fn
      {f, v} when is_binary(v) and f in [:brand, :model, :sku, :category] ->
        {f, v |> String.split("\n") |> hd()}

      {f, v} when is_binary(v) ->
        {f, String.replace(v, "\n", " ")}

      other ->
        other
    end)
    |> then(&Map.put(&1, :currency, Price.currency(&1[:price])))
  end

  defp linked_images(doc) do
    links =
      doc
      |> Floki.find("a[href]")
      |> Enum.filter(fn a -> image_url?(a |> Floki.attribute("href") |> List.first()) end)

    photos = Enum.flat_map(links, &Floki.attribute(&1, "href"))

    thumbs =
      links
      |> Enum.flat_map(&Floki.find(&1, "img"))
      |> Enum.map(fn {_, _, _} = img ->
        image_src(fn name -> img |> Floki.attribute(name) |> List.first() |> str() end)
      end)
      |> Enum.reject(&(is_nil(&1) or &1 in photos))

    %{photos: photos, thumbs: thumbs}
  end

  defp image_url?(nil), do: false
  defp image_url?(url), do: url =~ ~r/\.(jpe?g|png|webp)(\?|#|$)/i

  @size_words ~w(original orig xxl xl big large full medium md normal small sm thumbnails thumbnail thumbs thumb mini preview tiny)
  @size_rank %{
    "original" => 9,
    "orig" => 9,
    "xxl" => 8,
    "full" => 8,
    "xl" => 7,
    "big" => 7,
    "large" => 7,
    "medium" => 3,
    "md" => 3,
    "normal" => 3,
    "small" => 1,
    "sm" => 1,
    "thumbnails" => 0,
    "thumbnail" => 0,
    "thumbs" => 0,
    "thumb" => 0,
    "mini" => 0,
    "preview" => 0,
    "tiny" => 0
  }
  @size_params ~w(w h width height size resize fit quality q)

  @doc false
  def largest_sizes(urls) do
    keyed = Enum.with_index(urls, fn url, i -> {size_key(url), size_rank(url), i, url} end)

    keyed
    |> Enum.group_by(&elem(&1, 0))
    |> Enum.map(fn {_key, group} ->
      first = group |> Enum.map(&elem(&1, 2)) |> Enum.min()
      {_, _, _, best} = Enum.max_by(group, &{elem(&1, 1), -elem(&1, 2)})
      {first, best}
    end)
    |> Enum.sort()
    |> Enum.map(&elem(&1, 1))
  end

  defp size_key(url) do
    uri = URI.parse(url)
    words = Enum.join(@size_words, "|")

    path =
      (uri.path || "")
      |> String.replace(~r/(?<=[_\-.\/])(#{words})(?=[_\-.\/])/i, "*")
      |> String.replace(~r/[_\-]?\d{2,4}x\d{2,4}(?=[_\-.\/])/i, "")

    query =
      (uri.query || "")
      |> URI.decode_query()
      |> Map.drop(@size_params)

    {uri.host, path, query}
  end

  defp size_rank(url) do
    uri = URI.parse(url)
    path = String.downcase(uri.path || "")
    words = Enum.join(@size_words, "|")

    word =
      case Regex.run(~r/(?<=[_\-.\/])(#{words})(?=[_\-.\/])/, path) do
        [w | _] -> Map.fetch!(@size_rank, w)
        nil -> 5
      end

    dims =
      case Regex.run(~r/(\d{2,4})x(\d{2,4})(?=[_\-.\/])/, path) do
        [_, w, h] -> String.to_integer(w) * String.to_integer(h)
        nil -> nil
      end

    params = URI.decode_query(uri.query || "")
    width = Enum.find_value(~w(w width size), &(params[&1] && Integer.parse(params[&1])))

    cond do
      dims -> {word, dims}
      match?({_, _}, width) -> {word, elem(width, 0) * elem(width, 0)}
      true -> {word, :infinity}
    end
  end

  defp image_src(attr) do
    ~w(data-src data-lazy-src data-original src)
    |> Enum.map(attr)
    |> Enum.find(&(&1 && not String.starts_with?(&1, "data:")))
  end

  defp from_meta(doc) do
    meta =
      doc
      |> Floki.find("meta")
      |> Enum.reduce(%{}, fn el, acc ->
        key = (Floki.attribute(el, "property") ++ Floki.attribute(el, "name")) |> List.first()
        content = el |> Floki.attribute("content") |> List.first() |> str()

        if key && content,
          do: Map.update(acc, String.downcase(key), [content], &(&1 ++ [content])),
          else: acc
      end)

    one = fn keys -> Enum.find_value(keys, &List.first(meta[&1] || [])) end

    %{
      name: one.(~w(og:title twitter:title)),
      description: one.(~w(og:description twitter:description description)),
      photos:
        Enum.flat_map(
          ~w(og:image og:image:secure_url og:image:url twitter:image),
          &(meta[&1] || [])
        ),
      brand: one.(~w(product:brand og:brand)),
      category: one.(~w(product:category)),
      price: one.(~w(product:price:amount og:price:amount product:sale_price:amount)),
      currency: one.(~w(product:price:currency og:price:currency product:sale_price:currency)),
      url:
        with(
          u when is_binary(u) <- one.(~w(og:url)),
          true <- u =~ ~r{^https?://},
          do: u,
          else: (_ -> nil)
        )
    }
  end

  defp from_html(doc) do
    first = fn selector ->
      case Floki.find(doc, selector) do
        [el | _] -> el |> Floki.text(sep: " ") |> str()
        [] -> nil
      end
    end

    %{
      name: first.("h1") || first.("title"),
      url: doc |> Floki.find(~s(link[rel="canonical"])) |> Floki.attribute("href") |> List.first()
    }
  end

  @spec_label ~w(name label title)
  @max_depth 12

  defp state_specs(states) do
    states
    |> Enum.flat_map(&pairs_in(&1.data, 0))
    |> Enum.take(200)
  end

  defp pairs_in(_data, depth) when depth > @max_depth, do: []

  defp pairs_in(list, depth) when is_list(list) do
    pairs = Enum.flat_map(list, &state_pair/1)

    if length(pairs) >= 2 and length(pairs) * 2 >= length(list),
      do: pairs,
      else: Enum.flat_map(list, &pairs_in(&1, depth + 1))
  end

  defp pairs_in(%{} = map, depth), do: Enum.flat_map(map, fn {_, v} -> pairs_in(v, depth + 1) end)
  defp pairs_in(_, _), do: []

  defp state_pair(%{"value" => value} = item) when is_binary(value) or is_number(value) do
    with label when is_binary(label) <- Enum.find_value(@spec_label, &str(item[&1])),
         value when is_binary(value) <- str(value),
         true <- String.length(label) <= 40 and String.length(value) <= 300 do
      [{label, value}]
    else
      _ -> []
    end
  end

  defp state_pair(_), do: []

  @place_keys [
    ~w(street streetName streetAddress),
    ~w(districtName district),
    ~w(cityName city addressLocality locality town),
    ~w(regionName region addressRegion state)
  ]

  defp state_address(states) do
    Enum.find_value(states, fn s -> place_in(s.data, 0) end)
  end

  defp place_in(_data, depth) when depth > @max_depth, do: nil

  defp place_in(%{} = map, depth) do
    found =
      Enum.find_value(~w(location address), fn key ->
        case map[key] do
          %{} = place -> place_text(place)
          _ -> nil
        end
      end)

    found || Enum.find_value(map, fn {_, v} -> place_in(v, depth + 1) end)
  end

  defp place_in(list, depth) when is_list(list),
    do: Enum.find_value(list, &place_in(&1, depth + 1))

  defp place_in(_, _), do: nil

  defp place_text(place) do
    parts =
      for keys <- @place_keys,
          value = Enum.find_value(keys, &str(place[&1])),
          do: value

    if parts != [], do: parts |> Enum.uniq() |> Enum.join(", ")
  end

  defp states(doc) do
    json_scripts =
      doc
      |> Floki.find(~s(script[type="application/json"]))
      |> Enum.flat_map(fn {_, attrs, children} = el ->
        name =
          List.keyfind(attrs, "id", 0)
          |> case(
            do: (
              {_, id} -> id
              nil -> "json"
            )
          )

        decode_state(name, Enum.join(children), el)
      end)

    assigned =
      doc
      |> Floki.find("script:not([src])")
      |> Enum.flat_map(fn {_, _, children} -> assignments(Enum.join(children)) end)

    json_scripts ++ assigned
  end

  defp decode_state(name, json, _el) when byte_size(json) <= @max_state_bytes do
    case Jason.decode(json) do
      {:ok, data} when is_map(data) or is_list(data) -> [%{name: name, data: data}]
      _ -> []
    end
  end

  defp decode_state(_, _, _), do: []

  defp assignments(js) do
    ~r/(?:window|self|globalThis)\.([A-Za-z_$][\w$]*)\s*=\s*(?:JSON\.parse\(\s*)?/
    |> Regex.scan(js, return: :index)
    |> Enum.flat_map(fn [{start, len}, {ns, nl}] ->
      name = binary_part(js, ns, nl)
      rest = binary_part(js, start + len, byte_size(js) - start - len)

      with {:ok, literal} <- json_prefix(rest),
           {:ok, data} <- Jason.decode(literal),
           {:ok, data} <- maybe_inner(data) do
        [%{name: name, data: data}]
      else
        _ -> []
      end
    end)
  end

  defp maybe_inner(s) when is_binary(s) do
    case Jason.decode(s) do
      {:ok, data} when is_map(data) or is_list(data) -> {:ok, data}
      _ -> :error
    end
  end

  defp maybe_inner(data) when is_map(data) or is_list(data), do: {:ok, data}
  defp maybe_inner(_), do: :error

  @doc false
  def json_prefix(<<open, _::binary>> = text) when open in [?{, ?[, ?"] do
    case scan(text, 0, [], false, false) do
      nil -> :error
      len when len <= @max_state_bytes -> {:ok, binary_part(text, 0, len)}
      _ -> :error
    end
  end

  def json_prefix(_), do: :error

  defp scan(text, i, _stack, _in_str, _esc) when i >= byte_size(text), do: nil

  defp scan(text, i, stack, in_str, esc) do
    c = :binary.at(text, i)

    cond do
      in_str and esc -> scan(text, i + 1, stack, true, false)
      in_str and c == ?\\ -> scan(text, i + 1, stack, true, true)
      in_str and c == ?" and stack == [] -> i + 1
      in_str and c == ?" -> scan(text, i + 1, stack, false, false)
      in_str -> scan(text, i + 1, stack, true, false)
      c == ?" -> scan(text, i + 1, stack, true, false)
      c == ?{ -> scan(text, i + 1, [?} | stack], false, false)
      c == ?[ -> scan(text, i + 1, [?] | stack], false, false)
      stack != [] and c == hd(stack) and tl(stack) == [] -> i + 1
      stack != [] and c == hd(stack) -> scan(text, i + 1, tl(stack), false, false)
      true -> scan(text, i + 1, stack, false, false)
    end
  end
end
