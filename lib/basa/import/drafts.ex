defmodule Basa.Import.Drafts do
  alias Basa.Catalog
  alias Basa.Import
  alias Basa.Import.{Entry, Recipe}

  require Ash.Query

  @type outcome :: {:ok, Entry.t()} | {:error, term()}

  @spec import_page(Import.Source.t(), String.t(), map()) :: outcome()
  def import_page(source, url, actor) do
    opts = Import.source_opts(source) ++ [recipe: Recipe.load(source.recipe)]
    entry = find_entry(source, url)

    case Import.detect(url, opts) do
      {:ok, %{skip: true}} ->
        record(source, url, actor, %{status: :skipped, item_id: entry && entry.item_id})

      {:ok, result} ->
        fingerprint = fingerprint(result.fields)

        if entry && entry.item_id && entry.fingerprint == fingerprint do
          record(source, url, actor, %{
            status: :unchanged,
            item_id: entry.item_id,
            fingerprint: fingerprint
          })
        else
          save(source, url, actor, result, entry, fingerprint)
        end

      {:error, reason} ->
        record(source, url, actor, %{
          status: :failed,
          error: reason_text(reason),
          item_id: entry && entry.item_id
        })
    end
  end

  defp save(source, url, actor, result, entry, fingerprint) do
    item = entry && entry.item_id && get_item(entry.item_id, actor)
    attrs = item_attrs(source, result)

    {status, outcome} =
      case item do
        nil ->
          photos = download(result.fields[:photos] || [], actor, source)
          {:created, create_item(Map.put(attrs, :photos, photos), actor)}

        item ->
          attrs =
            if item.photos == [],
              do: Map.put(attrs, :photos, download(result.fields[:photos] || [], actor, source)),
              else: attrs

          {:updated, update_item(item, attrs, actor)}
      end

    case outcome do
      {:ok, item, note} ->
        record(source, url, actor, %{
          status: status,
          item_id: item.id,
          fingerprint: fingerprint,
          error: note
        })

      {:error, error} ->
        record(source, url, actor, %{
          status: :failed,
          error: reason_text(error),
          item_id: item && item.id
        })
    end
  end

  defp create_item(attrs, actor) do
    case Catalog.create_item(attrs, actor: actor) do
      {:ok, item} ->
        {:ok, item, nil}

      {:error, %Ash.Error.Invalid{} = error} when is_map_key(attrs, :category_id) ->
        if attrs_error?(error) do
          with {:ok, item} <-
                 Catalog.create_item(attrs |> Map.delete(:category_id) |> Map.put(:attrs, %{}),
                   actor: actor
                 ),
               do: {:ok, item, missing_note(error)}
        else
          {:error, error}
        end

      {:error, error} ->
        {:error, error}
    end
  end

  defp update_item(item, attrs, actor) do
    case Catalog.update_item(item, attrs, actor: actor) do
      {:ok, item} ->
        {:ok, item, nil}

      {:error, %Ash.Error.Invalid{} = error} ->
        if attrs_error?(error) do
          with {:ok, item} <-
                 Catalog.update_item(item, Map.drop(attrs, [:category_id, :attrs]), actor: actor),
               do: {:ok, item, missing_note(error)}
        else
          {:error, error}
        end

      {:error, error} ->
        {:error, error}
    end
  end

  defp attrs_error?(%Ash.Error.Invalid{errors: errors}),
    do: Enum.any?(errors, &(Map.get(&1, :field) == :attrs))

  defp missing_note(%Ash.Error.Invalid{errors: errors}) do
    details =
      errors
      |> Enum.filter(&(Map.get(&1, :field) == :attrs))
      |> Enum.map_join("; ", &Exception.message/1)

    "category not set, its details are missing: " <> details
  end

  @doc false
  def item_attrs(source, result) do
    f = result.fields
    category = category(source, f[:category])

    %{
      title: (f[:name] || f[:url] || "") |> String.slice(0, 200),
      description: f[:description],
      brand: f[:brand] && String.slice(f[:brand], 0, 200),
      model: f[:model] && String.slice(f[:model], 0, 200),
      attrs: attrs(category, result)
    }
    |> put_price(f[:price], f[:currency])
    |> then(&if(category, do: Map.put(&1, :category_id, category.id), else: &1))
  end

  defp put_price(attrs, %Decimal{} = price, currency) do
    case Enum.find(Basa.Money.currencies(), &(Atom.to_string(&1) == currency)) do
      nil -> attrs
      code -> Map.merge(attrs, %{estimated_value: price, currency: code})
    end
  end

  defp put_price(attrs, _, _), do: attrs

  defp category(source, site_category) do
    id = (site_category && source.category_map[site_category]) || source.default_category_id
    id && Ash.get!(Catalog.Category, id, authorize?: false, error?: false)
  end

  defp attrs(nil, _result), do: %{}

  defp attrs(category, result) do
    properties = get_in(category.attr_schema, ["properties"]) || %{}
    specs = Map.new(result.specs, fn {label, value} -> {String.downcase(label), value} end)

    from_specs =
      for {key, prop} <- properties,
          raw = specs[String.downcase(key)] || specs[String.downcase(prop["title"] || "")],
          value = cast(raw, prop),
          not is_nil(value),
          into: %{},
          do: {key, value}

    Map.merge(from_specs, Map.take(result[:attrs] || %{}, Map.keys(properties)))
  end

  defp cast(raw, %{"type" => "integer"}) do
    case Integer.parse(String.replace(raw, ~r/[^\d-]/u, "")) do
      {n, _} -> n
      :error -> nil
    end
  end

  defp cast(raw, %{"type" => "number"}) do
    case Basa.Import.Price.amount(raw) do
      nil -> nil
      d -> Decimal.to_float(d)
    end
  end

  defp cast(raw, %{"type" => "boolean"}) do
    down = String.downcase(String.trim(raw))

    cond do
      down in ~w(так є yes ja oui sí si tak da evet true 1 +) -> true
      down in ~w(ні немає no nein non nie nu hayır false 0 -) -> false
      true -> nil
    end
  end

  defp cast(raw, %{"enum" => values}),
    do: Enum.find(values, &(String.downcase(to_string(&1)) == String.downcase(raw)))

  defp cast(raw, _prop), do: raw

  defp download(urls, actor, source),
    do: Basa.Catalog.Photos.fetch(urls, actor.id, http: true, insecure: source.insecure)

  defp find_entry(source, url) do
    Entry
    |> Ash.Query.filter(source_id == ^source.id and url == ^url)
    |> Ash.read_one!(authorize?: false)
  end

  defp get_item(id, actor) do
    case Catalog.get_item(id, actor: actor) do
      {:ok, item} -> item
      _ -> nil
    end
  end

  defp record(source, url, actor, attrs) do
    Import.record_entry(Map.merge(%{url: url, source_id: source.id, error: nil}, attrs),
      actor: actor
    )
  end

  defp fingerprint(fields) do
    fields
    |> Enum.sort()
    |> Enum.map(fn {k, v} -> [to_string(k), to_string_value(v)] end)
    |> Jason.encode!()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp to_string_value(%Decimal{} = d), do: Decimal.to_string(d, :normal)
  defp to_string_value(list) when is_list(list), do: Enum.join(list, " ")
  defp to_string_value(v), do: to_string(v)

  defp reason_text(:bot_check), do: "bot check"
  defp reason_text({:http, status}), do: "HTTP #{status}"
  defp reason_text(%{__exception__: true} = e), do: Exception.message(e)
  defp reason_text(other), do: inspect(other)
end
