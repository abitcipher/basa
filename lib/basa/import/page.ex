defmodule Basa.Import.Page do
  alias Basa.Import.Charset

  @max_bytes 5_000_000
  @max_redirects 5

  @type t :: %{url: String.t(), content_type: String.t() | nil, body: String.t()}

  @spec get(String.t(), keyword()) :: {:ok, t()} | {:error, term()}
  def get(url, opts \\ []), do: get(url, opts, @max_redirects)

  defp get(_url, _opts, -1), do: {:error, :too_many_redirects}

  defp get(url, opts, redirects) do
    with {:ok, uri} <- check_url(url),
         {:ok, resp} <- request(URI.to_string(uri), opts) do
      case resp do
        %{status: s} when s in [301, 302, 303, 307, 308] ->
          case Req.Response.get_header(resp, "location") do
            [location | _] ->
              get(URI.merge(uri, location) |> URI.to_string(), opts, redirects - 1)

            [] ->
              {:error, :bad_redirect}
          end

        %{status: 200, private: %{too_large: true}} ->
          {:error, :too_large}

        %{status: 200, body: body} ->
          content_type = resp |> Req.Response.get_header("content-type") |> List.first()

          {:ok,
           %{
             url: URI.to_string(uri),
             content_type: content_type,
             body: Charset.to_utf8(body, content_type)
           }}

        %{status: s} ->
          {:error, {:http, s}}
      end
    end
  end

  defp request(url, opts) do
    tls = if opts[:insecure], do: [transport_opts: [verify: :verify_none]], else: []

    [
      url: url,
      redirect: false,
      retry: false,
      decode_body: false,
      compressed: false,
      headers: [
        {"user-agent", Basa.Import.user_agent()},
        {"accept", "text/html,application/xhtml+xml,application/json;q=0.9,*/*;q=0.8"},
        {"accept-language", "uk,en;q=0.8"}
      ],
      receive_timeout: 20_000,
      connect_options: [timeout: 10_000] ++ tls,
      into: fn {:data, data}, {req, resp} ->
        body = resp.body <> data

        if byte_size(body) > @max_bytes,
          do:
            {:halt, {req, %{resp | body: "", private: Map.put(resp.private, :too_large, true)}}},
          else: {:cont, {req, %{resp | body: body}}}
      end
    ]
    |> Keyword.merge(Basa.Import.req_options())
    |> Req.get()
  rescue
    e -> {:error, e}
  end

  def check_url(url) do
    uri = URI.parse(String.trim(url))

    cond do
      uri.scheme not in ["http", "https"] or uri.host in [nil, ""] -> {:error, :bad_url}
      not Basa.Import.check_hosts?() -> {:ok, uri}
      public_host?(uri.host) -> {:ok, uri}
      true -> {:error, :private_address}
    end
  end

  defp public_host?(host) do
    host = String.to_charlist(host)

    addresses =
      for family <- [:inet, :inet6],
          {:ok, addrs} <- [:inet.getaddrs(host, family)],
          addr <- addrs,
          do: addr

    addresses != [] and not Enum.any?(addresses, &Basa.Images.Fetch.private_ip?/1)
  end
end
