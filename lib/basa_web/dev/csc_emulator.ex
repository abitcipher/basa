defmodule BasaWeb.Dev.CscEmulator do
  use Plug.Router

  alias Basa.Witness.Native

  @seed "BASA dev CSC emulator"
  @max_age 600

  plug Plug.Parsers, parsers: [:urlencoded, :json], pass: ["*/*"], json_decoder: Jason
  plug :match
  plug :dispatch

  def anchors do
    {:ok, ca} = Native.qes_dev_ca(@seed)
    [ca]
  end

  def code(params, name) do
    sign("code", %{
      "name" => name,
      "scope" => params["scope"] || "service",
      "credential_id" => params["credentialID"],
      "hashes" => params["hashes"],
      "challenge" => params["code_challenge"],
      "redirect_uri" => params["redirect_uri"]
    })
  end

  get "/oauth2/authorize" do
    p = conn.query_params

    html = """
    <!doctype html><meta charset="utf-8"><title>CSC emulator</title>
    <body style="font-family:sans-serif;max-width:32rem;margin:3rem auto">
    <p style="font-size:.75rem;text-transform:uppercase;opacity:.6">Development only</p>
    <h1 style="font-size:1.2rem">Emulated remote signing service (CSC API)</h1>
    <p>#{if p["scope"] == "credential", do: "Approve one signature with your certificate.", else: "Sign in to your signing account."} Test certificates only: no legal effect.</p>
    <form method="post" action="authorize">
    #{for {k, v} <- p, into: "", do: ~s(<input type="hidden" name="#{esc(k)}" value="#{esc(v)}">)}
    <label>Name on the certificate <input id="csc-name" name="name" value="#{esc(known_name(p))}" required></label>
    <p><button id="csc-approve">Approve</button> <button id="csc-deny" name="deny" value="1">Deny</button></p>
    </form></body>
    """

    conn |> put_resp_content_type("text/html") |> send_resp(200, html)
  end

  post "/oauth2/authorize" do
    p = conn.body_params

    query =
      if p["deny"],
        do: %{"error" => "access_denied", "state" => p["state"]},
        else: %{"code" => code(p, p["name"]), "state" => p["state"]}

    conn
    |> put_resp_header("location", p["redirect_uri"] <> "?" <> URI.encode_query(query))
    |> send_resp(302, "")
  end

  post "/oauth2/token" do
    p = conn.body_params

    with "authorization_code" <- p["grant_type"],
         {:ok, c} <- verify("code", p["code"]),
         true <- c["redirect_uri"] == p["redirect_uri"],
         true <- pkce(p["code_verifier"]) == c["challenge"] do
      json(conn, 200, %{
        "access_token" => sign("token", Map.drop(c, ["challenge", "redirect_uri"])),
        "token_type" => "Bearer",
        "expires_in" => @max_age
      })
    else
      _ -> json(conn, 400, %{"error" => "invalid_grant"})
    end
  end

  post "/csc/v2/credentials/list" do
    with {:ok, t} <- bearer(conn), "service" <- t["scope"] do
      id = credential_id(t["name"])
      {:ok, {certs, nil}} = Native.qes_dev_remote(@seed, id, t["name"], nil)

      json(conn, 200, %{
        "credentialIDs" => [id],
        "credentialInfos" => [
          %{
            "credentialID" => id,
            "key" => %{
              "status" => "enabled",
              "algo" => ["1.2.840.10045.2.1"],
              "len" => 256,
              "curve" => "1.2.840.10045.3.1.7"
            },
            "cert" => %{"status" => "valid", "certificates" => Enum.map(certs, &Base.encode64/1)},
            "auth" => %{"mode" => "oauth2code"},
            "SCAL" => "2",
            "multisign" => 1
          }
        ]
      })
    else
      _ -> json(conn, 401, %{"error" => "invalid_token"})
    end
  end

  post "/csc/v2/signatures/signHash" do
    p = conn.body_params

    with {:ok, t} <- bearer(conn),
         "credential" <- t["scope"],
         true <- p["credentialID"] == t["credential_id"],
         [h] <- p["hashes"],
         {:ok, hash} <- Base.decode64(h),
         true <- Base.url_encode64(hash, padding: false) == t["hashes"],
         "1.2.840.10045.4.3.2" <- p["signAlgo"] do
      {:ok, {_certs, sig}} = Native.qes_dev_remote(@seed, t["credential_id"], t["name"], hash)
      json(conn, 200, %{"signatures" => [Base.encode64(sig)]})
    else
      _ -> json(conn, 400, %{"error" => "invalid_request"})
    end
  end

  match _ do
    send_resp(conn, 404, "")
  end

  defp credential_id(name), do: "emu-" <> Base.url_encode64(name, padding: false)

  defp known_name(%{"credentialID" => "emu-" <> encoded}) do
    case Base.url_decode64(encoded, padding: false) do
      {:ok, name} -> name
      :error -> ""
    end
  end

  defp known_name(p), do: p["name"] || ""

  defp pkce(nil), do: nil
  defp pkce(verifier), do: Base.url_encode64(:crypto.hash(:sha256, verifier), padding: false)

  defp bearer(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] -> verify("token", token)
      _ -> :error
    end
  end

  defp sign(kind, data), do: Phoenix.Token.sign(BasaWeb.Endpoint, "csc emulator " <> kind, data)

  defp verify(kind, value) when is_binary(value),
    do: Phoenix.Token.verify(BasaWeb.Endpoint, "csc emulator " <> kind, value, max_age: @max_age)

  defp verify(_, _), do: :error

  defp json(conn, status, body) do
    conn |> put_resp_content_type("application/json") |> send_resp(status, Jason.encode!(body))
  end

  defp esc(v), do: v |> to_string() |> Plug.HTML.html_escape()
end
