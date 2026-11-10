defmodule Basa.TrustedQESProvider do
  @behaviour Basa.Witness.QES.Provider

  @seed "trusted provider for tests"

  @impl true
  def anchors do
    {:ok, ca} = Basa.Witness.Native.qes_dev_ca(@seed)
    [%{certificate: ca, provider: :trusted, test?: false}]
  end

  @impl true
  def start(record, _tx, _party, _return_url),
    do: {:ok, "/nowhere/" <> Base.url_encode64(record.state, padding: false)}

  @impl true
  def complete(record, params), do: Basa.Witness.QES.DevProvider.complete(record, params)

  def sign(user_id, name, hash), do: Basa.Witness.Native.qes_dev_sign(@seed, user_id, name, hash)

  def with_trusted(fun) do
    old = Application.get_env(:basa, Basa.Witness.QES)

    Application.put_env(:basa, Basa.Witness.QES,
      providers: [:dev, :trusted],
      modules: %{trusted: __MODULE__}
    )

    try do
      fun.()
    after
      Application.put_env(:basa, Basa.Witness.QES, old)
    end
  end
end
