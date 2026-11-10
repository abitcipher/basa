defmodule Basa.MemFixtures do
  def phone do
    {public, private} = :crypto.generate_key(:eddsa, :ed25519)
    %{public: public, private: private}
  end

  def attest_pair(origin, subject, requests, opts \\ []) do
    [r1, r2] = opts[:roles] || ["offeror", "acceptor"]
    p1 = requests["offeror"].phone
    p2 = requests["acceptor"].phone
    a1 = {p1.public, r1, :crypto.strong_rand_bytes(16)}
    a2 = {p2.public, r2, :crypto.strong_rand_bytes(16)}
    [lo, hi] = Enum.sort_by([a1, a2], &elem(&1, 0))
    st = statement(opts[:origin] || origin, opts[:subject] || subject, lo, hi)

    {sign(st, requests["offeror"].challenge, p1), sign(st, requests["acceptor"].challenge, p2)}
  end

  def statement(origin, subject, {pk_lo, role_lo, nonce_lo}, {pk_hi, role_hi, nonce_hi}) do
    map([
      {0, uint(1)},
      {1, text(origin)},
      {2, bytes(subject)},
      {3, bytes(pk_lo)},
      {4, text(role_lo)},
      {5, bytes(nonce_lo)},
      {6, bytes(pk_hi)},
      {7, text(role_hi)},
      {8, bytes(nonce_hi)}
    ])
  end

  def sign(statement, challenge, phone) do
    message = "MEM/v1/attestation" <> challenge <> statement
    signature = :crypto.sign(:eddsa, :none, message, [phone.private, :ed25519])

    map([
      {0, uint(1)},
      {1, bytes(statement)},
      {2, bytes(challenge)},
      {3, bytes(phone.public)},
      {4, bytes(signature)}
    ])
  end

  def text_form(bytes), do: "memattsig1:" <> Base.url_encode64(bytes, padding: false)

  defp map(entries),
    do:
      [head(5, length(entries)) | Enum.map(entries, fn {k, v} -> [uint(k), v] end)]
      |> IO.iodata_to_binary()

  defp uint(n), do: head(0, n)
  defp text(s), do: [head(3, byte_size(s)), s] |> IO.iodata_to_binary()
  defp bytes(b), do: [head(2, byte_size(b)), b] |> IO.iodata_to_binary()

  defp head(major, n) when n < 24, do: <<major::3, n::5>>
  defp head(major, n) when n < 256, do: <<major::3, 24::5, n>>
  defp head(major, n) when n < 65_536, do: <<major::3, 25::5, n::16>>
end
