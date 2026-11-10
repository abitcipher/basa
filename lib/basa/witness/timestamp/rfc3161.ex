defmodule Basa.Witness.Timestamp.RFC3161 do
  @behaviour Basa.Witness.Timestamp

  @impl true
  def stamp(<<_::binary-size(32)>> = hash) do
    in_tmp(fn dir ->
      query = Path.join(dir, "req.tsq")
      reply = Path.join(dir, "reply.tsr")

      with {_, 0} <- openssl(~w(ts -query -sha256 -cert -digest #{hex(hash)} -out #{query})),
           {:ok, %{status: 200, body: body}} <-
             Req.post(url(),
               body: File.read!(query),
               headers: [{"content-type", "application/timestamp-query"}],
               retry: false,
               receive_timeout: 15_000
             ),
           :ok <- File.write(reply, body),
           {:ok, time} <- check(reply, hash) do
        {:ok, %{token: body, time: time}}
      else
        {:ok, %{status: status}} -> {:error, {:tsa_http, status}}
        {:error, _} = error -> error
        {out, code} when is_binary(out) -> {:error, {:openssl, code, out}}
      end
    end)
  end

  @impl true
  def verify(token, <<_::binary-size(32)>> = hash) do
    in_tmp(fn dir ->
      reply = Path.join(dir, "reply.tsr")
      File.write!(reply, token)
      check(reply, hash)
    end)
  end

  defp check(reply, hash) do
    certs = Application.app_dir(:basa, "priv/witness/tsa/#{certificates()}")

    verify_args =
      ~w(ts -verify -digest #{hex(hash)} -in #{reply} -CAfile #{Path.join(certs, "cacert.pem")} -untrusted #{Path.join(certs, "tsa.crt")})

    with {out, 0} <- openssl(verify_args),
         true <- out =~ "Verification: OK" || {:error, :not_verified},
         {text, 0} <- openssl(~w(ts -reply -in #{reply} -text)),
         [_, stamp] <- Regex.run(~r/Time stamp: (.+ GMT)/, text) || {:error, :no_time} do
      parse_time(stamp)
    else
      {:error, _} = error -> error
      {_out, _code} -> {:error, :not_verified}
    end
  end

  defp parse_time(stamp) do
    months = ~w(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec)

    with [mon, day, time, year, "GMT"] <- String.split(stamp),
         m when is_integer(m) <- Enum.find_index(months, &(&1 == mon)),
         [hh, mm, ss] <- String.split(time, ":"),
         {:ok, dt} <-
           NaiveDateTime.new(
             String.to_integer(year),
             m + 1,
             String.to_integer(day),
             String.to_integer(hh),
             String.to_integer(mm),
             ss |> String.split(".") |> hd() |> String.to_integer()
           ) do
      {:ok, DateTime.from_naive!(dt, "Etc/UTC")}
    else
      _ -> {:error, {:bad_time, stamp}}
    end
  end

  defp openssl(args), do: System.cmd("openssl", args, stderr_to_stdout: true)

  defp in_tmp(fun) do
    dir = Path.join(System.tmp_dir!(), "basa-tsa-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)

    try do
      fun.(dir)
    after
      File.rm_rf(dir)
    end
  end

  defp hex(bin), do: Base.encode16(bin, case: :lower)
  defp url, do: Basa.Witness.Timestamp.config()[:url] || "https://freetsa.org/tsr"
  defp certificates, do: Basa.Witness.Timestamp.config()[:certificates] || "freetsa"
end
