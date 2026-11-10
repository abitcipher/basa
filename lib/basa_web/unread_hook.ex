defmodule BasaWeb.UnreadHook do
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [attach_hook: 4, connected?: 1]
  require Ash.Query

  def on_mount(:default, _params, _session, socket) do
    case socket.assigns[:current_user] do
      nil ->
        {:cont, assign(socket, :unread_count, 0)}

      user ->
        if connected?(socket),
          do: Phoenix.PubSub.subscribe(Basa.PubSub, Basa.Events.user_topic(user.id))

        socket =
          socket
          |> assign(:unread_count, count(user))
          |> attach_hook(:unread, :handle_info, fn
            {:unread_changed, _}, socket ->
              {:halt, assign(socket, :unread_count, count(user))}

            _other, socket ->
              if function_exported?(socket.view, :handle_info, 2),
                do: {:cont, socket},
                else: {:halt, socket}
          end)

        {:cont, socket}
    end
  end

  def count(user) do
    Basa.Messaging.Conversation
    |> Ash.Query.filter(
      (lessor_id == ^user.id and lessor_unread == true) or
        (lessee_id == ^user.id and lessee_unread == true)
    )
    |> Ash.count!(actor: user)
  end
end
