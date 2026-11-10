defmodule BasaWeb.KeepState do
  use Phoenix.Component

  @salt "keep-state"
  @max_age 24 * 60 * 60

  def start(socket, key, initial) do
    assign(socket, keep: %{key: key, base: :erlang.phash2(initial), user: user_id(socket)})
  end

  def restore(socket, token) when is_binary(token) do
    %{key: key, base: base, user: user} = socket.assigns.keep

    case Phoenix.Token.decrypt(BasaWeb.Endpoint, @salt, token, max_age: @max_age) do
      {:ok, {^user, ^key, ^base, data}} -> {:ok, data}
      _ -> :error
    end
  end

  def restore(_socket, _token), do: :error

  def forget(socket),
    do: Phoenix.LiveView.push_event(socket, "keep:forget", %{key: socket.assigns.keep.key})

  attr :keep, :map, required: true
  attr :data, :any, required: true

  def kept(assigns) do
    ~H"""
    <div
      id={"keep-" <> String.replace(@keep.key, ":", "-")}
      phx-hook="KeepState"
      data-key={@keep.key}
      data-token={token(@keep, @data)}
      hidden
    >
    </div>
    """
  end

  defp token(%{key: key, base: base, user: user}, data),
    do: Phoenix.Token.encrypt(BasaWeb.Endpoint, @salt, {user, key, base, data})

  defp user_id(socket), do: socket.assigns[:current_user] && socket.assigns.current_user.id
end
