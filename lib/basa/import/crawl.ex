defmodule Basa.Import.Crawl do
  alias Basa.Import.{Browser, Page}

  @next_words ~w(next наступна наступна» далі далее weiter suivant siguiente successivo
                 następna următoarea sonraki » › >> >)
  @max_sitemaps 5

  @type found :: %{urls: [String.t()], pages: non_neg_integer()}

  @spec discover(map()) :: {:ok, found()} | {:error, term()}
  def discover(source) do
    {urls, pages} = from_catalogue(source)
    urls = if source.use_sitemap, do: urls ++ from_sitemap(source), else: urls
    urls = urls |> Enum.uniq() |> Enum.take(source.max_items)

    cond do
      urls != [] -> {:ok, %{urls: urls, pages: pages}}
      source.catalogue_urls == [] and not source.use_sitemap -> {:error, :no_catalogue}
      true -> {:ok, %{urls: [], pages: pages}}
    end
  end

  defp from_catalogue(source) do
    queue = :queue.from_list(source.catalogue_urls)
    walk(source, queue, MapSet.new(source.catalogue_urls), 0, [])
  end

  defp walk(source, queue, seen, pages, acc) do
    done? = pages >= source.max_pages or length(Enum.uniq(acc)) >= source.max_items

    case {done?, :queue.out(queue)} do
      {false, {{:value, url}, queue}} ->
        case html(source, url) do
          {:ok, html, page_url} ->
            doc = Floki.parse_document!(html)
            next = next_link(doc, page_url, source.next_selector)

            lists =
              if source.list_pattern in [nil, ""],
                do: [],
                else: links(doc, page_url, source.list_pattern)

            more = Enum.reject([next | lists], &(is_nil(&1) or MapSet.member?(seen, &1)))

            walk(
              source,
              Enum.reduce(more, queue, &:queue.in/2),
              Enum.reduce(more, MapSet.put(seen, page_url), &MapSet.put(&2, &1)),
              pages + 1,
              acc ++ links(doc, page_url, source.link_pattern)
            )

          {:error, _} ->
            walk(source, queue, seen, pages + 1, acc)
        end

      _ ->
        {acc, pages}
    end
  end

  defp html(source, url) do
    if source.browser == :always do
      with {:ok, page} <- Browser.render(url, insecure: source.insecure),
           do: {:ok, page.html, page.url}
    else
      with {:ok, page} <- Page.get(url, insecure: source.insecure), do: {:ok, page.body, page.url}
    end
  end

  @spec links(Floki.html_tree() | String.t(), String.t(), String.t() | nil) :: [String.t()]
  def links(html, base, pattern) when is_binary(html),
    do: links(Floki.parse_document!(html), base, pattern)

  def links(doc, base, pattern) do
    host = URI.parse(base).host

    doc
    |> Floki.find("a[href]")
    |> Floki.attribute("href")
    |> Enum.map(&absolute(&1, base))
    |> Enum.filter(&(is_binary(&1) and URI.parse(&1).host == host and matches?(&1, pattern)))
    |> Enum.uniq()
  end

  @spec next_link(Floki.html_tree() | String.t(), String.t(), String.t() | nil) ::
          String.t() | nil
  def next_link(html, base, selector) when is_binary(html),
    do: next_link(Floki.parse_document!(html), base, selector)

  def next_link(doc, base, selector) do
    host = URI.parse(base).host

    candidates =
      if is_binary(selector) and String.trim(selector) != "" do
        safe_find(doc, selector)
      else
        Floki.find(doc, ~s(link[rel="next"], a[rel="next"])) ++
          Enum.filter(Floki.find(doc, "a[href]"), &next_text?/1)
      end

    candidates
    |> Enum.flat_map(&(Floki.attribute(&1, "href") ++ Floki.attribute(&1, "data-href")))
    |> Enum.map(&absolute(&1, base))
    |> Enum.find(&(is_binary(&1) and &1 != strip(base) and URI.parse(&1).host == host))
  end

  defp next_text?(a) do
    text = a |> Floki.text() |> String.trim() |> String.downcase()
    label = a |> Floki.attribute("aria-label") |> List.first("") |> String.downcase()
    text in @next_words or String.trim(label) in @next_words
  end

  defp safe_find(doc, selector) do
    Floki.find(doc, selector)
  rescue
    _ -> []
  end

  defp from_sitemap(source) do
    case List.first(source.catalogue_urls) || List.first(source.sample_urls) do
      nil ->
        []

      url ->
        uri = URI.parse(url)
        sitemap = "#{uri.scheme}://#{uri.authority}/sitemap.xml"

        source
        |> sitemap_urls([sitemap], @max_sitemaps, [])
        |> Enum.filter(&matches?(&1, source.link_pattern))
    end
  end

  defp sitemap_urls(_source, [], _left, acc), do: acc
  defp sitemap_urls(_source, _queue, 0, acc), do: acc

  defp sitemap_urls(source, [url | rest], left, acc) do
    case Page.get(url, insecure: source.insecure) do
      {:ok, %{body: xml}} ->
        {pages, sitemaps} = sitemap_locs(xml)
        sitemap_urls(source, rest ++ sitemaps, left - 1, acc ++ pages)

      _ ->
        sitemap_urls(source, rest, left - 1, acc)
    end
  end

  @spec sitemap_locs(String.t()) :: {[String.t()], [String.t()]}
  def sitemap_locs(xml) do
    locs = fn tag ->
      ~r{<#{tag}>.*?<loc>\s*(.*?)\s*</loc>}s
      |> Regex.scan(xml)
      |> Enum.map(fn [_, loc] -> loc |> String.replace("&amp;", "&") end)
    end

    {locs.("url"), locs.("sitemap")}
  end

  def valid_pattern?(nil), do: true
  def valid_pattern?(""), do: true

  def valid_pattern?(pattern) do
    case regex(pattern) do
      {:ok, _} -> true
      :plain -> true
      :error -> false
    end
  end

  defp matches?(_url, pattern) when pattern in [nil, ""], do: true

  defp matches?(url, pattern) do
    case regex(pattern) do
      {:ok, re} -> Regex.match?(re, url)
      :plain -> String.contains?(url, pattern)
      :error -> false
    end
  end

  defp regex("re:" <> source) do
    case Regex.compile(source) do
      {:ok, re} -> {:ok, re}
      _ -> :error
    end
  end

  defp regex(_plain), do: :plain

  defp absolute(href, base) do
    href = String.trim(href)

    if href == "" or String.starts_with?(href, ["#", "javascript:", "mailto:", "tel:"]) do
      nil
    else
      base |> URI.merge(href) |> URI.to_string() |> strip()
    end
  rescue
    _ -> nil
  end

  defp strip(url), do: url |> String.split("#") |> hd()
end
