defmodule Basa.Images.Fetch do
  @max_bytes 10_000_000
  @max_redirects 3

  @spec image(String.t(), keyword()) :: {:ok, binary(), String.t()} | {:error, term()}
  def image(url, opts \\ []), do: get(url, opts, @max_redirects)

  defp get(_url, _opts, -1), do: {:error, :too_many_redirects}

  defp get(url, opts, redirects) do
    with {:ok, uri} <- check_url(url, opts),
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
          case type(body) do
            nil -> {:error, :not_an_image}
            type -> {:ok, body, type}
          end

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
      headers: [{"user-agent", Basa.Images.user_agent()}],
      receive_timeout: 15_000,
      connect_options: [timeout: 5_000] ++ tls,
      into: fn {:data, data}, {req, resp} ->
        body = resp.body <> data

        if byte_size(body) > @max_bytes,
          do:
            {:halt, {req, %{resp | body: "", private: Map.put(resp.private, :too_large, true)}}},
          else: {:cont, {req, %{resp | body: body}}}
      end
    ]
    |> Keyword.merge(Basa.Images.req_options())
    |> Req.get()
  rescue
    e -> {:error, e}
  end

  def check_url(url, opts \\ []) do
    uri = URI.parse(url)
    schemes = if opts[:http], do: ["https", "http"], else: ["https"]

    cond do
      uri.scheme not in schemes or uri.host in [nil, ""] -> {:error, :not_https}
      not Basa.Images.check_hosts?() -> {:ok, uri}
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

    addresses != [] and not Enum.any?(addresses, &private_ip?/1)
  end

  def private_ip?({a, b, _, _}) do
    a in [0, 10, 127] or
      (a == 100 and b in 64..127) or
      (a == 169 and b == 254) or
      (a == 172 and b in 16..31) or
      (a == 192 and b == 168) or
      a >= 224
  end

  def private_ip?({0, 0, 0, 0, 0, 0, 0, _}), do: true

  def private_ip?({0, 0, 0, 0, 0, 0xFFFF, hi, lo}),
    do: private_ip?({div(hi, 256), rem(hi, 256), div(lo, 256), rem(lo, 256)})

  def private_ip?({a, _, _, _, _, _, _, _}),
    do: a in 0xFC00..0xFDFF or a in 0xFE80..0xFEBF or a >= 0xFF00

  defp type(<<0xFF, 0xD8, 0xFF, _::binary>>), do: "image/jpeg"
  defp type(<<0x89, "PNG", 0x0D, 0x0A, 0x1A, 0x0A, _::binary>>), do: "image/png"
  defp type(<<"RIFF", _::binary-size(4), "WEBP", _::binary>>), do: "image/webp"
  defp type(_), do: nil
end
