defmodule Basa.Payments.Gateway.Fake do
  @behaviour Basa.Payments.Gateway

  def start, do: Agent.start(fn -> %{} end, name: __MODULE__) |> then(fn _ -> :ok end)

  def set_status(id, status), do: Agent.update(__MODULE__, &Map.put(&1, id, status))

  @impl true
  def create_checkout(%{reference: ref}) do
    id = "fake_" <> ref
    set_status(id, :pending)
    {:ok, %{provider_payment_id: id, payment_url: "https://pay.test/" <> id}}
  end

  @impl true
  def fetch_status(id), do: {:ok, Agent.get(__MODULE__, &Map.get(&1, id, :pending))}

  @impl true
  def verify_webhook(body, sig) do
    expected = :crypto.mac(:hmac, :sha512, "test", body) |> Base.encode16(case: :lower)
    if sig == expected, do: :ok, else: {:error, :invalid_signature}
  end
end
