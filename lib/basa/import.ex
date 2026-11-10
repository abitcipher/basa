defmodule Basa.Import do
  use Ash.Domain, otp_app: :basa, extensions: [AshJsonApi.Domain]

  alias Basa.Import.{Access, Agreement, Browser, Detect, Entry, Page, Source}

  require Ash.Query

  json_api do
    routes do
      base_route "/import/sources", Source do
        index :mine
        get :read
        post :create
        patch :update
        delete :destroy
        route :post, "/:id/crawl", :crawl
        route :post, "/:id/import", :import_page
      end

      base_route "/import/entries", Entry do
        index :read
        get :read
      end
    end
  end

  resources do
    resource Agreement do
      define :publish_agreement, action: :publish, args: [:body]
    end

    resource Access do
      define :grant_access, action: :grant, args: [:user_id]
      define :revoke_access, action: :revoke
      define :accept_agreement, action: :accept, args: [:version]
    end

    resource Source do
      define :create_source, action: :create
      define :update_source, action: :update
      define :set_source_insecure, action: :set_insecure, args: [:insecure]
      define :record_crawl, action: :crawled
      define :destroy_source, action: :destroy
      define :get_source, action: :read, get_by: [:id]
      define :list_sources, action: :read
    end

    resource Entry do
      define :record_entry, action: :record
      define :list_entries, action: :read
    end
  end

  @spec current_agreement() :: Agreement.t() | nil
  def current_agreement do
    Agreement
    |> Ash.Query.sort(version: :desc)
    |> Ash.Query.limit(1)
    |> Ash.read_one!(authorize?: false)
  end

  def access_for(nil), do: nil

  def access_for(user) do
    Access
    |> Ash.Query.filter(user_id == ^user.id)
    |> Ash.read_one!(authorize?: false)
  end

  @spec status(map() | nil) :: :ok | :confirm | :no_agreement | :none
  def status(user) do
    case access_for(user) do
      %Access{revoked_at: nil} = access ->
        case current_agreement() do
          nil -> :no_agreement
          %{version: v} when access.accepted_version == v -> :ok
          _ -> :confirm
        end

      _ ->
        :none
    end
  end

  def allowed?(user), do: status(user) == :ok

  def source_opts(source) do
    browser =
      case source.browser do
        :always -> true
        :never -> false
        _ -> :auto
      end

    [browser: browser, insecure: source.insecure]
  end

  def source_with_owner(id) do
    with {:ok, source} <- Ash.get(Source, id, authorize?: false),
         {:ok, owner} <- Ash.get(Basa.Accounts.User, source.owner_id, authorize?: false),
         do: {:ok, source, owner}
  end

  def crawl_now(source, actor) do
    if source.owner_id == actor.id and allowed?(actor) do
      {:ok, _} = Oban.insert(Basa.Import.CrawlWorker.new(%{source_id: source.id}))
      :ok
    else
      {:error, :forbidden}
    end
  end

  defdelegate import_page(source, url, actor), to: Basa.Import.Drafts

  @spec grant_by_email(String.t(), keyword()) :: {:ok, Access.t()} | {:error, :no_user | term()}
  def grant_by_email(email, opts) do
    email = email |> to_string() |> String.trim() |> String.downcase()

    Basa.Accounts.User
    |> Ash.Query.filter(fragment("lower(?)", email) == ^email)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, %{id: id}} -> grant_access(id, opts)
      _ -> {:error, :no_user}
    end
  end

  def list_access(opts) do
    with {:ok, rows} <- Access |> Ash.Query.sort(granted_at: :desc) |> Ash.read(opts) do
      users =
        Basa.Accounts.User
        |> Ash.Query.filter(id in ^Enum.map(rows, & &1.user_id))
        |> Ash.read!(authorize?: false)
        |> Map.new(&{&1.id, to_string(&1.email)})

      {:ok, Enum.map(rows, &Map.put(&1, :email, users[&1.user_id]))}
    end
  end

  def configured?, do: Keyword.get(config(), :enabled, true)

  def enabled?, do: configured?() and Basa.Services.on?(:import)

  @spec detect(String.t(), keyword()) ::
          {:ok, Detect.result() | %{via: :fast | :browser}} | {:error, term()}
  def detect(url, opts \\ []) do
    found =
      cond do
        not enabled?() -> {:error, :switched_off}
        opts[:browser] == true -> rendered(url, opts)
        opts[:browser] == false -> fast(url, opts)
        true -> auto(url, opts)
      end

    case {found, opts[:recipe]} do
      {{:ok, result}, %{} = recipe} ->
        Basa.Import.Recipe.apply(recipe, result, result.fields[:url] || url)

      _ ->
        found
    end
  end

  defp auto(url, opts) do
    case fast(url, opts) do
      {:ok, result} = ok ->
        if thin?(result) and Browser.available?(), do: better(rendered(url, opts), ok), else: ok

      {:error, {:http, _}} = refused ->
        if Browser.available?(), do: better(rendered(url, opts), refused), else: refused

      error ->
        error
    end
  end

  defp better({:ok, r}, {:ok, f}), do: if(score(r) >= score(f), do: {:ok, r}, else: {:ok, f})
  defp better({:ok, _} = r, _), do: r
  defp better({:error, :bot_check} = check, {:error, _}), do: check
  defp better(_, fallback), do: fallback

  defp thin?(%{fields: f}), do: not (Map.has_key?(f, :price) or Map.has_key?(f, :photos))
  defp score(%{fields: f}), do: map_size(f)

  defp fast(url, opts) do
    with {:ok, page} <- Page.get(url, opts),
         do:
           {:ok, page.body |> Detect.page(page.url) |> Map.merge(%{via: :fast, html: page.body})}
  end

  defp rendered(url, opts) do
    with {:ok, page} <-
           Browser.render(url,
             insecure: opts[:insecure] || false,
             user_agent: config()[:user_agent]
           ),
         :ok <- answered(page.status, page.html) do
      result =
        page.html
        |> Detect.page(page.url)
        |> fill_from(page.source && Detect.page(page.source, page.url))

      loaded =
        for j <- page.json, {:ok, data} <- [Jason.decode(j.body)], do: %{name: j.url, data: data}

      {:ok,
       %{result | states: result.states ++ loaded} |> Map.merge(%{via: :browser, html: page.html})}
    end
  end

  defp fill_from(result, nil), do: result

  defp fill_from(result, original) do
    %{
      result
      | fields: Map.merge(original.fields, result.fields),
        sources: Map.merge(original.sources, result.sources),
        specs: Enum.uniq_by(result.specs ++ original.specs, &String.downcase(elem(&1, 0))),
        json_ld: Enum.uniq(result.json_ld ++ original.json_ld),
        states: Enum.uniq_by(result.states ++ original.states, & &1.name)
    }
  end

  defp answered(status, html) do
    cond do
      bot_check?(status, html) -> {:error, :bot_check}
      is_integer(status) and status >= 400 -> {:error, {:http, status}}
      true -> :ok
    end
  end

  @challenge ~w(/cdn-cgi/challenge-platform challenges.cloudflare.com cf-chl-)
  @captcha ~w(g-recaptcha google.com/recaptcha hcaptcha.com captcha-delivery.com
              _Incapsula_Resource px-captcha)

  @doc false
  def bot_check?(status, html) do
    String.contains?(html, @challenge) or
      (status in [401, 403, 429, 503] and String.contains?(html, @captcha))
  end

  def user_agent,
    do:
      config()[:user_agent] ||
        "Mozilla/5.0 (compatible; BASA-import/#{Application.spec(:basa, :vsn)})"

  @doc false
  def req_options, do: config()[:req_options] || []

  @doc false
  def check_hosts?, do: Keyword.get(config(), :check_hosts, true)

  defp config, do: Application.get_env(:basa, __MODULE__, [])
end
