defmodule Basa.Witness.Timestamp.Fake do
  @behaviour Basa.Witness.Timestamp

  @impl true
  def stamp(<<_::binary-size(32)>> = hash) do
    time = DateTime.utc_now() |> DateTime.truncate(:second)
    {:ok, %{token: "fake:" <> hash <> DateTime.to_iso8601(time), time: time}}
  end

  @impl true
  def verify("fake:" <> <<hash::binary-size(32), time::binary>>, hash) do
    {:ok, time, _} = DateTime.from_iso8601(time)
    {:ok, time}
  end

  def verify(_token, _hash), do: {:error, :not_verified}
end
