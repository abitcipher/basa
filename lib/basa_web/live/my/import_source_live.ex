defmodule BasaWeb.My.ImportSourceLive do
  use BasaWeb, :live_view

  alias Basa.Import
  alias Basa.Import.{Detect, Recipe, Selector}
  alias RulesEngine, as: Engine

  @tabs ~w(found pick rules test catalogue)

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    user = socket.assigns.current_user

    with true <- Import.allowed?(user),
         {:ok, source} <- Import.get_source(id, actor: user) do
      {:ok,
       socket
       |> assign(page_title: source.name, source: source, recipe: Recipe.load(source.recipe))
       |> assign(tab: "found", sample: 0, raw: nil, result: nil, error: nil, reading?: false)
       |> assign(field: "price", suggestions: nil, tests: nil, testing?: false, dirty?: false)
       |> assign(importing?: false, categories: categories(), links: nil, finding?: false)
       |> load_entries()}
    else
      _ ->
        {:ok,
         socket
         |> put_flash(:error, gettext("This source is not available."))
         |> push_navigate(to: ~p"/my/import")}
    end
  end

  @impl true
  def handle_params(params, _uri, socket) do
    tab = if params["tab"] in @tabs, do: params["tab"], else: "found"
    socket = assign(socket, tab: tab)

    {:noreply,
     if(tab in ~w(pick rules) and is_nil(socket.assigns[:raw]) and connected?(socket),
       do: read(socket),
       else: socket
     )}
  end

  @impl true
  def handle_event("tab", %{"tab" => tab}, socket) when tab in @tabs do
    {:noreply, push_patch(socket, to: ~p"/my/import/#{socket.assigns.source.id}?tab=#{tab}")}
  end

  def handle_event("read", params, socket) do
    sample = String.to_integer(params["sample"] || "#{socket.assigns.sample}")
    {:noreply, socket |> assign(sample: sample) |> read()}
  end

  def handle_event("settings", %{"settings" => params}, socket) do
    urls = (params["urls"] || "") |> String.split(~r/\s+/, trim: true) |> Enum.uniq()

    attrs = %{name: params["name"], sample_urls: urls, browser: params["browser"]}

    case Import.update_source(socket.assigns.source, attrs, actor: socket.assigns.current_user) do
      {:ok, source} ->
        {:noreply,
         socket
         |> assign(source: source, sample: 0, page_title: source.name)
         |> put_flash(:info, gettext("Saved."))}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, Enum.join(BasaWeb.ErrorText.messages(error), "; "))}
    end
  end

  def handle_event("field", %{"field" => field}, socket),
    do: {:noreply, assign(socket, field: field, suggestions: nil)}

  def handle_event("picked", picked, socket) do
    case socket.assigns.raw do
      %{html: html} ->
        picked = %{
          chain: Enum.map(picked["chain"] || [], &node_info/1),
          text: picked["text"],
          src: picked["src"]
        }

        {:noreply, assign(socket, suggestions: Selector.suggest(html, picked))}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("use", %{"index" => index}, socket) do
    %{rule: rule} = Enum.at(socket.assigns.suggestions, String.to_integer(index))
    field = String.to_existing_atom(socket.assigns.field)

    rule = if field == :photos, do: all_photos(rule), else: rule
    recipe = socket.assigns.recipe
    save_recipe(socket, %{recipe | fields: Map.put(recipe.fields, field, rule)})
  end

  def handle_event("forget", %{"field" => field}, socket) do
    field = String.to_existing_atom(field)

    save_recipe(socket, %{
      socket.assigns.recipe
      | fields: Map.delete(socket.assigns.recipe.fields, field)
    })
  end

  def handle_event("changed", _params, socket), do: {:noreply, assign(socket, dirty?: true)}

  def handle_event("json_error", %{"message" => message}, socket),
    do:
      {:noreply,
       put_flash(socket, :error, gettext("The JSON isn't valid: %{error}", error: message))}

  def handle_event("save_graph", %{"graph" => graph}, socket) do
    case Engine.validate(graph) do
      :ok ->
        rules = if graph_empty?(graph), do: nil, else: graph

        socket
        |> assign(dirty?: false)
        |> push_event("rules:saved", %{})
        |> save_recipe(%{socket.assigns.recipe | rules: rules})

      {:error, message} ->
        {:noreply,
         put_flash(socket, :error, gettext("The rules aren't valid: %{error}", error: message))}
    end
  end

  def handle_event("simulate", %{"graph" => graph, "context" => context_json}, socket) do
    reply =
      with {:ok, context} <- Jason.decode(context_json),
           {:ok, response} <- Engine.simulate(graph, context) do
        %{result: Map.put(response, "snapshot", graph)}
      else
        {:error, %Jason.DecodeError{} = e} ->
          %{error: %{title: gettext("Test input"), message: Exception.message(e), data: %{}}}

        {:error, reason} ->
          %{error: %{title: gettext("Rule error"), message: inspect(reason), data: %{}}}
      end

    {:reply, %{simulate: reply}, socket}
  end

  def handle_event("categories", %{"map" => map} = params, socket) do
    category_map = for {site, id} <- map, id != "", into: %{}, do: {site, id}
    default = if params["default"] in [nil, ""], do: nil, else: params["default"]

    case Import.update_source(
           socket.assigns.source,
           %{category_map: category_map, default_category_id: default},
           actor: socket.assigns.current_user
         ) do
      {:ok, source} ->
        {:noreply, socket |> assign(source: source) |> put_flash(:info, gettext("Saved."))}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, Enum.join(BasaWeb.ErrorText.messages(error), "; "))}
    end
  end

  def handle_event("categories", params, socket),
    do: handle_event("categories", Map.put(params, "map", %{}), socket)

  def handle_event("import", params, socket) do
    %{source: source, current_user: user} = socket.assigns
    urls = if params["url"], do: [params["url"]], else: source.sample_urls

    {:noreply,
     socket
     |> assign(importing?: true)
     |> start_async(:import, fn ->
       Enum.map(urls, &Import.import_page(source, &1, user))
     end)}
  end

  def handle_event("catalogue", %{"catalogue" => p}, socket) do
    attrs = %{
      catalogue_urls: (p["urls"] || "") |> String.split(~r/\s+/, trim: true) |> Enum.uniq(),
      link_pattern: blank(p["link_pattern"]),
      list_pattern: blank(p["list_pattern"]),
      next_selector: blank(p["next_selector"]),
      use_sitemap: p["use_sitemap"] == "true",
      max_pages: p["max_pages"],
      max_items: p["max_items"],
      refresh: p["refresh"]
    }

    case Import.update_source(socket.assigns.source, attrs, actor: socket.assigns.current_user) do
      {:ok, source} ->
        {:noreply,
         socket |> assign(source: source, links: nil) |> put_flash(:info, gettext("Saved."))}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, Enum.join(BasaWeb.ErrorText.messages(error), "; "))}
    end
  end

  def handle_event("find_links", _params, socket) do
    source = socket.assigns.source

    {:noreply,
     socket
     |> assign(finding?: true, links: nil)
     |> start_async(:links, fn -> Basa.Import.Crawl.discover(source) end)}
  end

  def handle_event("crawl", _params, socket) do
    case Import.crawl_now(socket.assigns.source, socket.assigns.current_user) do
      :ok ->
        {:noreply,
         put_flash(
           socket,
           :info,
           gettext("Crawling started: pages are imported one by one, a few seconds apart.")
         )}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("This source is not available."))}
    end
  end

  def handle_event("refresh_entries", _params, socket) do
    {:ok, source} =
      Import.get_source(socket.assigns.source.id, actor: socket.assigns.current_user)

    {:noreply, socket |> assign(source: source) |> load_entries()}
  end

  def handle_event("test", _params, socket) do
    %{source: source, recipe: recipe} = socket.assigns
    opts = detect_opts(source) ++ [recipe: recipe]

    {:noreply,
     socket
     |> assign(testing?: true, tests: nil)
     |> start_async(:test, fn ->
       source.sample_urls
       |> Task.async_stream(&{&1, Import.detect(&1, opts)},
         timeout: 90_000,
         max_concurrency: 2,
         on_timeout: :kill_task
       )
       |> Enum.zip(source.sample_urls)
       |> Enum.map(fn
         {{:ok, row}, _} -> row
         {{:exit, _}, url} -> {url, {:error, :timeout}}
       end)
     end)}
  end

  @impl true
  def handle_async(:read, {:ok, {:ok, raw}}, socket) do
    {:noreply, socket |> assign(raw: raw, reading?: false, error: nil) |> apply_recipe()}
  end

  def handle_async(:read, {:ok, {:error, reason}}, socket),
    do: {:noreply, assign(socket, reading?: false, raw: nil, result: nil, error: reason)}

  def handle_async(:read, {:exit, _}, socket),
    do: {:noreply, assign(socket, reading?: false, error: :timeout)}

  def handle_async(:test, {:ok, rows}, socket),
    do: {:noreply, assign(socket, tests: rows, testing?: false)}

  def handle_async(:test, {:exit, _}, socket), do: {:noreply, assign(socket, testing?: false)}

  def handle_async(:import, {:ok, _}, socket),
    do:
      {:noreply,
       socket
       |> assign(importing?: false)
       |> load_entries()
       |> put_flash(:info, gettext("Imported as drafts in your items."))}

  def handle_async(:import, {:exit, _}, socket),
    do: {:noreply, socket |> assign(importing?: false) |> load_entries()}

  def handle_async(:links, {:ok, found}, socket),
    do: {:noreply, assign(socket, links: found, finding?: false)}

  def handle_async(:links, {:exit, _}, socket),
    do: {:noreply, assign(socket, links: {:error, :timeout}, finding?: false)}

  defp blank(nil), do: nil
  defp blank(s), do: if(String.trim(s) == "", do: nil, else: String.trim(s))

  defp load_entries(socket) do
    entries =
      Import.list_entries!(
        actor: socket.assigns.current_user,
        query: [filter: [source_id: socket.assigns.source.id], sort: [imported_at: :desc]]
      )

    assign(socket, entries: entries)
  end

  defp categories do
    locale = Gettext.get_locale(BasaWeb.Gettext)

    Basa.Catalog.list_categories!(authorize?: false)
    |> Enum.sort_by(& &1.position)
    |> Enum.map(&{&1.id, Basa.Catalog.Category.display_name(&1, locale)})
  end

  defp site_categories(nil, map), do: Map.keys(map)

  defp site_categories(tests, map) do
    found = for {_, {:ok, r}} <- tests, c = r.fields[:category], is_binary(c), do: c
    Enum.uniq(found ++ Map.keys(map))
  end

  defp read(socket) do
    url = Enum.at(socket.assigns.source.sample_urls, socket.assigns.sample)
    opts = detect_opts(socket.assigns.source)

    socket
    |> assign(reading?: true, error: nil, suggestions: nil)
    |> start_async(:read, fn -> Import.detect(url, opts) end)
  end

  defp detect_opts(source), do: Import.source_opts(source)

  defp apply_recipe(%{assigns: %{raw: nil}} = socket), do: assign(socket, result: nil)

  defp apply_recipe(socket) do
    %{raw: raw, recipe: recipe} = socket.assigns

    case Recipe.apply(recipe, raw, raw.fields[:url] || current_url(socket)) do
      {:ok, result} -> assign(socket, result: result)
      {:error, reason} -> assign(socket, result: Map.put(raw, :skip, false), error: reason)
    end
  end

  defp save_recipe(socket, recipe) do
    case Import.update_source(socket.assigns.source, %{recipe: Recipe.dump(recipe)},
           actor: socket.assigns.current_user
         ) do
      {:ok, source} ->
        {:noreply,
         socket |> assign(source: source, recipe: recipe, suggestions: nil) |> apply_recipe()}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, Enum.join(BasaWeb.ErrorText.messages(error), "; "))}
    end
  end

  defp current_url(%{assigns: assigns}), do: current_url(assigns)
  defp current_url(assigns), do: Enum.at(assigns.source.sample_urls, assigns.sample)

  defp node_info(n) do
    %{
      tag: to_string(n["tag"] || ""),
      id: n["id"],
      classes: List.wrap(n["classes"]),
      attrs: Map.take(n["attrs"] || %{}, ~w(itemprop)),
      nth: n["nth"]
    }
  end

  defp all_photos(%{from: :css, selector: s} = rule),
    do: %{rule | selector: String.replace(s, ~r/:nth-of-type\(\d+\)/, "")}

  defp all_photos(rule), do: rule

  defp graph_empty?(%{"nodes" => nodes}),
    do:
      Enum.all?(
        nodes,
        &(&1["type"] in ["inputNode", "outputNode"] or &1["content"]["expressions"] in [nil, []])
      )

  defp graph_empty?(_), do: true

  @doc false
  def starter_graph do
    %{
      "nodes" => [
        %{
          "id" => "input",
          "type" => "inputNode",
          "name" => "Request",
          "position" => %{"x" => 40, "y" => 200}
        },
        %{
          "id" => "map",
          "type" => "expressionNode",
          "name" => "Fields",
          "position" => %{"x" => 300, "y" => 200},
          "content" => %{"expressions" => []}
        },
        %{
          "id" => "output",
          "type" => "outputNode",
          "name" => "Response",
          "position" => %{"x" => 560, "y" => 200}
        }
      ],
      "edges" => [
        %{"id" => "in", "sourceId" => "input", "targetId" => "map", "type" => "edge"},
        %{"id" => "out", "sourceId" => "map", "targetId" => "output", "type" => "edge"}
      ]
    }
  end

  defp rules_context(raw) do
    Jason.encode!(
      %{
        "fields" =>
          Map.new(raw.fields, fn {k, v} ->
            {k, if(is_struct(v, Decimal), do: Decimal.to_float(v), else: v)}
          end),
        "specs" => Map.new(raw.specs),
        "url" => raw.fields[:url]
      },
      pretty: true
    )
  end

  @dropped ~w(script noscript iframe frame object embed base)

  @doc false
  def preview(html, url) do
    html
    |> Floki.parse_document!()
    |> Floki.traverse_and_update(fn
      {tag, _, _} when tag in @dropped ->
        nil

      {"meta", attrs, _} = el ->
        if(refresh?(attrs), do: nil, else: el)

      {tag, attrs, children} ->
        {tag, attrs |> Enum.reject(&unsafe_attr?/1) |> Enum.map(&absolute(&1, url)), children}

      other ->
        other
    end)
    |> Floki.raw_html()
  end

  @url_attrs ~w(href src data-src data-lazy-src data-original poster)

  defp absolute({k, v}, base) when k in @url_attrs do
    {k, base |> URI.merge(String.trim(v)) |> URI.to_string()}
  rescue
    _ -> {k, v}
  end

  defp absolute({"srcset", v}, base) do
    srcset =
      v
      |> String.split(",")
      |> Enum.map_join(", ", fn part ->
        case String.split(String.trim(part), ~r/\s+/, parts: 2) do
          [src | rest] -> Enum.join([elem(absolute({"src", src}, base), 1) | rest], " ")
          [] -> part
        end
      end)

    {"srcset", srcset}
  end

  defp absolute(attr, _base), do: attr

  defp refresh?(attrs),
    do: Enum.any?(attrs, fn {k, v} -> k == "http-equiv" and String.downcase(v) == "refresh" end)

  defp unsafe_attr?({"on" <> _, _}), do: true

  defp unsafe_attr?({k, v}) when k in ["href", "src", "action", "formaction"],
    do: v |> String.trim() |> String.downcase() |> String.starts_with?("javascript:")

  defp unsafe_attr?(_), do: false

  defp fields_list, do: Detect.fields()

  defp field_label(:name), do: gettext("Name")
  defp field_label(:description), do: gettext("Description")
  defp field_label(:price), do: gettext("Price")
  defp field_label(:currency), do: gettext("Currency")
  defp field_label(:photos), do: gettext("Photos")
  defp field_label(:brand), do: gettext("Brand")
  defp field_label(:model), do: gettext("Model")
  defp field_label(:sku), do: gettext("Article number")
  defp field_label(:category), do: gettext("Category")
  defp field_label(:address), do: gettext("Address")
  defp field_label(:area), do: gettext("Area")
  defp field_label(:rooms), do: gettext("Rooms")
  defp field_label(:url), do: gettext("Page address")

  defp entry_status(:created), do: gettext("Added as a draft")
  defp entry_status(:updated), do: gettext("Draft updated")
  defp entry_status(:unchanged), do: gettext("Unchanged since the last import")
  defp entry_status(:skipped), do: gettext("Skipped by the rules")
  defp entry_status(:failed), do: gettext("Not imported")

  defp source_label(:json_ld), do: "JSON-LD"
  defp source_label(:microdata), do: "Microdata"
  defp source_label(:meta), do: "OpenGraph"
  defp source_label(:specs), do: gettext("Details")
  defp source_label(:gallery), do: gettext("Gallery")
  defp source_label(:state), do: gettext("Page data")
  defp source_label(:html), do: gettext("Page")
  defp source_label(:recipe), do: gettext("Your pick")
  defp source_label(:rules), do: gettext("Rules")
  defp source_label(_), do: ""

  defp display(%Decimal{} = d), do: Decimal.to_string(d, :normal)
  defp display(list) when is_list(list), do: ngettext("1 photo", "%{count} photos", length(list))
  defp display(s) when is_binary(s), do: String.slice(s, 0, 200)
  defp display(other), do: inspect(other)

  defp rule_text(%{from: :spec, label: label}), do: gettext("next to “%{label}”", label: label)
  defp rule_text(%{from: :css, selector: s}), do: s

  defp error_text(:bot_check),
    do: gettext("The site answered with a bot check; BASA does not get past those.")

  defp error_text(:switched_off), do: gettext("Import from web pages is switched off for now.")
  defp error_text(:timeout), do: gettext("The page took too long to read.")

  defp error_text({:http, status}),
    do: gettext("The site answered with an error (%{status}).", status: status)

  defp error_text({:rules, _}),
    do: gettext("The rules stopped with an error; the result is shown without them.")

  defp error_text(_), do: gettext("The page could not be read.")

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} unread={@unread_count} wide>
      <div class="mb-3">
        <.back_button navigate={~p"/my/import"} label={gettext("Import from web pages")} class="mb-1" />
        <h1 class="text-xl font-bold">{@source.name}</h1>
      </div>

      <nav id="source-tabs" class="mb-4 flex flex-wrap gap-2">
        <.button
          :for={
            {tab, label} <- [
              {"found", gettext("Found")},
              {"pick", gettext("Pick")},
              {"rules", gettext("Rules")},
              {"catalogue", gettext("Catalogue")},
              {"test", gettext("Test")}
            ]
          }
          id={"tab-#{tab}"}
          size="small"
          color={if @tab == tab, do: "primary", else: "natural"}
          variant={if @tab == tab, do: "default", else: "bordered"}
          phx-click="tab"
          phx-value-tab={tab}
        >
          {label}
        </.button>
      </nav>

      <form
        :if={@tab in ~w(found pick)}
        id="sample-form"
        phx-change="read"
        class="mb-4 flex flex-wrap items-end gap-2"
      >
        <div class="min-w-0 flex-1">
          <.native_select
            id="sample-select"
            name="sample"
            label={gettext("Sample page")}
            size="medium"
          >
            <:option
              :for={{url, i} <- Enum.with_index(@source.sample_urls)}
              value={i}
              selected={i == @sample}
            >
              {url}
            </:option>
          </.native_select>
        </div>
        <.button
          id="read-page"
          type="button"
          color="primary"
          variant="default"
          phx-click="read"
          phx-disable-with={gettext("Reading…")}
        >
          {if @raw, do: gettext("Read again"), else: gettext("Read page")}
        </.button>
      </form>

      <p :if={@reading?} id="reading" class="mb-4 text-sm opacity-70">
        {gettext("Reading the page…")}
      </p>
      <p :if={@error} id="read-error" class="mb-4 text-sm text-red-600">{error_text(@error)}</p>

      <div :if={@tab == "found"} class="grid gap-6 lg:grid-cols-[2fr_1fr]">
        <section>
          <.card :if={@result} id="found" padding="small" rounded="large">
            <p :if={@result[:skip]} id="skipped" class="mb-2 text-sm font-medium">
              {gettext("The rules skip this page.")}
            </p>
            <p class="mb-2 text-xs opacity-60">
              {if @result.via == :browser,
                do: gettext("Read in the browser"),
                else: gettext("Read without a browser")}
            </p>
            <dl class="divide-y divide-zinc-100 text-sm dark:divide-zinc-800">
              <div :for={field <- fields_list()} id={"found-#{field}"} class="flex gap-3 py-1.5">
                <dt class="w-32 shrink-0 opacity-70">{field_label(field)}</dt>
                <dd class="min-w-0 flex-1 break-words">
                  <span :if={Map.has_key?(@result.fields, field)}>{display(@result.fields[field])}</span>
                  <span :if={!Map.has_key?(@result.fields, field)} class="opacity-40">—</span>
                </dd>
                <dd :if={@result.sources[field]} class="shrink-0">
                  <.badge size="extra_small" variant="bordered">
                    {source_label(@result.sources[field])}
                  </.badge>
                </dd>
              </div>
            </dl>
          </.card>
          <.button
            :if={@result}
            id="import-this"
            class="mt-3"
            color="primary"
            variant="default"
            phx-click="import"
            phx-value-url={current_url(assigns)}
            phx-disable-with={gettext("Importing…")}
          >
            {gettext("Import this page as a draft")}
          </.button>
          <.empty_state
            :if={is_nil(@result) and not @reading?}
            title={gettext("Read a sample page to see what BASA finds on it.")}
          />
        </section>

        <.card padding="medium" rounded="large">
          <h2 class="mb-2 font-semibold">{gettext("Source")}</h2>
          <form id="settings-form" phx-submit="settings" class="space-y-3">
            <.text_field
              id="settings-name"
              name="settings[name]"
              value={@source.name}
              label={gettext("Name")}
              size="medium"
            />
            <.textarea_field
              id="settings-urls"
              name="settings[urls]"
              value={Enum.join(@source.sample_urls, "\n")}
              rows="4"
              label={gettext("Sample pages, one address per line (up to 5)")}
            />
            <.native_select
              id="settings-browser"
              name="settings[browser]"
              label={gettext("Browser")}
              size="medium"
            >
              <:option value="auto" selected={@source.browser == :auto}>
                {gettext("When needed")}
              </:option>
              <:option value="always" selected={@source.browser == :always}>
                {gettext("Always")}
              </:option>
              <:option value="never" selected={@source.browser == :never}>{gettext("Never")}</:option>
            </.native_select>
            <.button type="submit" color="primary" variant="default">{gettext("Save")}</.button>
          </form>
        </.card>
      </div>

      <div :if={@tab == "pick"} class="grid gap-4 lg:grid-cols-[1fr_22rem]">
        <section>
          <div
            :if={@raw}
            id="page-picker"
            phx-hook="PagePicker"
            class="relative overflow-hidden rounded-xl border border-zinc-200 dark:border-zinc-800"
          >
            <iframe
              id="page-preview"
              sandbox="allow-same-origin"
              srcdoc={preview(@raw.html, current_url(assigns))}
              class="h-[70vh] w-full bg-white"
              title={gettext("Page preview")}
            ></iframe>
            <div data-picker-layer class="absolute inset-0 cursor-crosshair"></div>
          </div>
        </section>

        <aside class="space-y-3">
          <form id="field-form" phx-change="field">
            <.native_select
              id="pick-field"
              name="field"
              label={gettext("Field to pick")}
              size="medium"
            >
              <:option :for={f <- fields_list()} value={f} selected={to_string(f) == @field}>
                {field_label(f)}
              </:option>
            </.native_select>
          </form>
          <p class="text-sm opacity-70">{gettext("Click the value on the page.")}</p>

          <div :if={@suggestions} id="suggestions" class="space-y-2">
            <p :if={@suggestions == []} id="no-suggestions" class="text-sm opacity-70">
              {gettext("No rule picks exactly this; try the element around the value.")}
            </p>
            <.card
              :for={{s, i} <- Enum.with_index(@suggestions)}
              id={"suggestion-#{i}"}
              padding="small"
              rounded="large"
            >
              <p class="break-all font-mono text-xs">{rule_text(s.rule)}</p>
              <p class="my-1 text-sm">{display(s.value)}</p>
              <.button
                size="small"
                color="primary"
                variant="default"
                phx-click="use"
                phx-value-index={i}
              >
                {gettext("Use for %{field}", field: field_label(String.to_existing_atom(@field)))}
              </.button>
            </.card>
          </div>

          <div :if={@recipe.fields != %{}} id="picked-rules" class="space-y-1">
            <h2 class="text-sm font-semibold">{gettext("Your picks")}</h2>
            <div
              :for={{field, rule} <- @recipe.fields}
              id={"rule-#{field}"}
              class="flex items-center justify-between gap-2 text-sm"
            >
              <span class="min-w-0 truncate">{field_label(field)}:
              <span class="font-mono text-xs">{rule_text(rule)}</span></span>
              <.button
                size="extra_small"
                variant="bordered"
                phx-click="forget"
                phx-value-field={field}
              >{gettext("Remove")}</.button>
            </div>
          </div>
        </aside>
      </div>

      <div :if={@tab == "rules"}>
        <div class="mb-2 flex flex-wrap items-center justify-end gap-2">
          <span :if={@dirty?} class="text-sm opacity-70">{gettext("Unsaved changes")}</span>
          <.info_tip id="source-rules-info" align="end">
            {gettext(
              "The rules get the fields found (fields.price, fields.name…), the page's details (specs['Label']) and its address (url). Outputs named like a field replace it; skip set to true leaves the page out."
            )}
          </.info_tip>
          <.button
            id="source-rules-test"
            variant="bordered"
            phx-click={JS.dispatch("rules:simulate", to: "#rules-editor")}
          >
            {gettext("Test")}
          </.button>
          <.button
            id="source-rules-save"
            color="primary"
            variant="default"
            phx-click={JS.dispatch("rules:save", to: "#rules-editor")}
          >
            {gettext("Save")}
          </.button>
        </div>
        <div
          :if={@raw}
          id="rules-editor"
          phx-hook="RulesEditor"
          data-graph={Jason.encode!(@recipe.rules || starter_graph())}
          data-context={rules_context(@raw)}
        >
          <div class="basa-editor-pane overflow-hidden rounded-xl border border-zinc-200 bg-white dark:border-zinc-800">
            <div data-editor-root phx-update="ignore" id="rules-editor-root" class="h-full"></div>
          </div>
          <div class="hidden" data-json-root phx-update="ignore" id="rules-json-root"></div>
          <div class="hidden" id="rules-context" phx-update="ignore"></div>
        </div>
      </div>

      <div :if={@tab == "test"}>
        <.button
          id="run-test"
          color="primary"
          variant="default"
          phx-click="test"
          phx-disable-with={gettext("Testing…")}
          class="mb-4"
        >
          {gettext("Test on every sample page")}
        </.button>
        <p :if={@testing?} class="text-sm opacity-70">{gettext("Reading the pages…")}</p>
        <div :if={@tests} id="test-results" class="space-y-2">
          <.card
            :for={{{url, outcome}, i} <- Enum.with_index(@tests)}
            id={"test-#{i}"}
            padding="small"
            rounded="large"
          >
            <p class="truncate text-xs opacity-60">{url}</p>
            <%= case outcome do %>
              <% {:ok, r} -> %>
                <p :if={r[:skip]} class="text-sm font-medium">{gettext("Skipped by the rules")}</p>
                <p :if={!r[:skip]} class="text-sm">
                  <span class="font-medium">{r.fields[:name] || "—"}</span>
                  · {if r.fields[:price],
                    do: "#{display(r.fields.price)} #{r.fields[:currency]}",
                    else: gettext("no price")} · {display(r.fields[:photos] || [])}
                </p>
              <% {:error, reason} -> %>
                <p class="text-sm text-red-600">{error_text(reason)}</p>
            <% end %>
          </.card>
        </div>

        <.card padding="medium" rounded="large" class="mt-6">
          <h2 class="mb-2 font-semibold">{gettext("Categories")}</h2>
          <form id="categories-form" phx-submit="categories" class="space-y-3">
            <.native_select
              :for={{site, i} <- Enum.with_index(site_categories(@tests, @source.category_map))}
              id={"category-map-#{i}"}
              name={"map[#{site}]"}
              label={site}
              size="medium"
            >
              <:option value="">{gettext("Not mapped")}</:option>
              <:option
                :for={{id, name} <- @categories}
                value={id}
                selected={@source.category_map[site] == id}
              >
                {name}
              </:option>
            </.native_select>
            <.native_select
              id="category-default"
              name="default"
              label={gettext("Everything else")}
              size="medium"
            >
              <:option value="">{gettext("No category")}</:option>
              <:option
                :for={{id, name} <- @categories}
                value={id}
                selected={@source.default_category_id == id}
              >
                {name}
              </:option>
            </.native_select>
            <.button type="submit" variant="bordered">{gettext("Save")}</.button>
          </form>
        </.card>

        <div class="mt-6 flex flex-wrap items-center gap-2">
          <.button
            id="import-all"
            color="primary"
            variant="default"
            phx-click="import"
            disabled={@importing?}
            phx-disable-with={gettext("Importing…")}
          >
            {gettext("Import every sample page as a draft")}
          </.button>
          <.info_tip id="import-drafts-info">
            {gettext(
              "Imported pages become items in your inventory, seen only by you until you make an offer of them. Importing a page again updates its item."
            )}
          </.info_tip>
        </div>
        <p :if={@importing?} id="importing" class="mt-2 text-sm opacity-70">
          {gettext("Importing…")}
        </p>
      </div>

      <div :if={@tab == "catalogue"} class="grid gap-6 lg:grid-cols-[1fr_1fr]">
        <.card padding="medium" rounded="large">
          <div class="mb-2 flex items-center gap-2">
            <h2 class="font-semibold">{gettext("Catalogue")}</h2>
            <.info_tip id="catalogue-info">
              {gettext(
                "BASA reads the catalogue pages, follows their next pages and imports every item page whose address contains the given piece (/catalog/product/details/). For a regular expression, start with re: (re:/p/\\d+$)."
              )}
            </.info_tip>
          </div>
          <form id="catalogue-form" phx-submit="catalogue" class="space-y-3">
            <.textarea_field
              id="catalogue-urls"
              name="catalogue[urls]"
              value={Enum.join(@source.catalogue_urls, "\n")}
              rows="3"
              label={gettext("Catalogue pages, one address per line")}
              placeholder="https://"
            />
            <.text_field
              id="catalogue-pattern"
              name="catalogue[link_pattern]"
              value={@source.link_pattern}
              label={gettext("Item addresses contain")}
              size="medium"
            />
            <.text_field
              id="catalogue-lists"
              name="catalogue[list_pattern]"
              value={@source.list_pattern}
              label={gettext("List pages contain (optional)")}
              size="medium"
            />
            <.text_field
              id="catalogue-next"
              name="catalogue[next_selector]"
              value={@source.next_selector}
              label={gettext("Next page link (CSS, optional)")}
              size="medium"
            />
            <.checkbox_field
              id="catalogue-sitemap"
              name="catalogue[use_sitemap]"
              value="true"
              checked={@source.use_sitemap}
              label={gettext("Also use the site's sitemap")}
            />
            <div class="grid grid-cols-2 gap-3">
              <.number_field
                id="catalogue-max-pages"
                name="catalogue[max_pages]"
                value={@source.max_pages}
                label={gettext("Catalogue pages at most")}
                min="1"
                max="100"
                size="medium"
              />
              <.number_field
                id="catalogue-max-items"
                name="catalogue[max_items]"
                value={@source.max_items}
                label={gettext("Items at most")}
                min="1"
                max="2000"
                size="medium"
              />
            </div>
            <.native_select
              id="catalogue-refresh"
              name="catalogue[refresh]"
              label={gettext("Read again")}
              size="medium"
            >
              <:option value="off" selected={@source.refresh == :off}>
                {gettext("Only when I ask")}
              </:option>
              <:option value="daily" selected={@source.refresh == :daily}>
                {gettext("Every night")}
              </:option>
              <:option value="weekly" selected={@source.refresh == :weekly}>
                {gettext("Every week")}
              </:option>
            </.native_select>
            <.button type="submit" color="primary" variant="default">{gettext("Save")}</.button>
          </form>
        </.card>

        <section class="space-y-3">
          <div class="flex flex-wrap gap-2">
            <.button id="find-links" variant="bordered" phx-click="find_links" disabled={@finding?}>
              {gettext("Find links")}
            </.button>
            <.button id="crawl-now" color="primary" variant="default" phx-click="crawl">
              {gettext("Crawl and import now")}
            </.button>
            <.button
              id="refresh-entries"
              variant="transparent"
              phx-click="refresh_entries"
              icon="hero-arrow-path"
            >
              {gettext("Refresh")}
            </.button>
          </div>

          <p :if={@source.last_crawl_at} id="last-crawl" class="text-sm opacity-80">
            {gettext("Last crawl: %{when}, %{count} item pages found.",
              when: Calendar.strftime(@source.last_crawl_at, "%Y-%m-%d %H:%M"),
              count: @source.last_crawl_found || 0
            )}
            <span :if={@source.last_crawl_error} class="text-red-600">{@source.last_crawl_error}</span>
          </p>

          <p :if={@finding?} class="text-sm opacity-70">{gettext("Reading the pages…")}</p>
          <div :if={match?({:ok, _}, @links)} id="found-links">
            <% {:ok, found} = @links %>
            <p class="mb-1 text-sm font-medium">
              {gettext("%{count} item pages on %{pages} catalogue pages.",
                count: length(found.urls),
                pages: found.pages
              )}
            </p>
            <ul class="space-y-0.5 text-xs opacity-80">
              <li :for={url <- Enum.take(found.urls, 15)} class="truncate">{url}</li>
            </ul>
          </div>
          <p :if={match?({:error, _}, @links)} id="links-error" class="text-sm text-red-600">
            {gettext("Add catalogue pages or the sitemap first.")}
          </p>
        </section>
      </div>

      <section :if={@entries != [] and @tab in ~w(found test catalogue)} id="entries" class="mt-6">
        <h2 class="mb-2 font-semibold">{gettext("Imported")}</h2>
        <div class="space-y-2">
          <.card :for={e <- @entries} id={"entry-#{e.id}"} padding="small" rounded="large">
            <div class="flex flex-wrap items-center justify-between gap-2">
              <div class="min-w-0">
                <p class="truncate text-xs opacity-60">{e.url}</p>
                <p class="text-sm">
                  {entry_status(e.status)}
                  <span :if={e.error} class="opacity-70">· {e.error}</span>
                </p>
              </div>
              <.button_link
                :if={e.item_id}
                size="small"
                variant="bordered"
                navigate={~p"/my/items/#{e.item_id}"}
              >
                {gettext("Open item")}
              </.button_link>
            </div>
          </.card>
        </div>
      </section>
    </Layouts.app>
    """
  end
end
