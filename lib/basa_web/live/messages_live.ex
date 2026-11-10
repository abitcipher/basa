defmodule BasaWeb.MessagesLive do
  use BasaWeb, :live_view

  alias Basa.Messaging
  alias Basa.Messaging.Conversation

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket, page_title: gettext("Messages"), conversation: nil, messages: [], sent: 0)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    socket =
      assign(socket,
        conversations: Messaging.list_my_conversations!(actor: socket.assigns.current_user)
      )

    {:noreply, open(socket, socket.assigns.live_action, params)}
  end

  defp open(socket, :index, _), do: assign(socket, conversation: nil)

  defp open(socket, :show, %{"id" => id}) do
    user = socket.assigns.current_user

    case Messaging.get_conversation(id, actor: user, load: [:lot, :lessor, :lessee]) do
      {:ok, conv} ->
        if connected?(socket) do
          if old = socket.assigns.conversation,
            do: Phoenix.PubSub.unsubscribe(Basa.PubSub, topic(old.id))

          Phoenix.PubSub.subscribe(Basa.PubSub, topic(conv.id))
          if Conversation.unread_for?(conv, user.id), do: read(conv, user)
        end

        assign(socket,
          conversation: conv,
          messages: Messaging.list_messages!(conv.id, actor: user)
        )

      {:error, _} ->
        socket
        |> put_flash(:error, gettext("Conversation not found."))
        |> push_patch(to: ~p"/messages")
    end
  end

  defp read(conv, user) do
    Messaging.mark_read!(conv, actor: user)
    Basa.Events.notify_user(user.id, {:unread_changed, conv.id})
  end

  @impl true
  def handle_event("send", %{"body" => body}, socket) do
    %{conversation: conv, current_user: user} = socket.assigns

    case Messaging.send_message(conv.id, body, actor: user) do
      {:ok, _} -> {:noreply, update(socket, :sent, &(&1 + 1))}
      {:error, _} -> {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:new_message, message}, socket) do
    %{conversation: conv, current_user: user} = socket.assigns

    if conv && message.conversation_id == conv.id do
      if message.sender_id != user.id, do: read(conv, user)

      {:noreply,
       socket
       |> update(:messages, &(&1 ++ [message]))
       |> push_event("chat:scroll", %{})}
    else
      {:noreply, socket}
    end
  end

  def handle_info(_other, socket), do: {:noreply, socket}

  defp topic(id), do: Basa.Messaging.Changes.Deliver.topic(id)

  defp other_name(conv, me) do
    other = if conv.lessor_id == me.id, do: conv.lessee, else: conv.lessor
    Layouts.display_name(other)
  end

  defp time(dt), do: Calendar.strftime(dt, "%d.%m %H:%M")

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      unread={@unread_count}
      active={:messages}
      wide
    >
      <div class="grid gap-4 md:grid-cols-[18rem_1fr]">
        <aside class={[@conversation && "hidden md:block"]}>
          <.page_title title={gettext("Messages")} />
          <div class="space-y-2">
            <.link :for={c <- @conversations} patch={~p"/messages/#{c.id}"} class="block">
              <.card
                padding="small"
                rounded="large"
                color={if @conversation && @conversation.id == c.id, do: "primary", else: "natural"}
                variant={if @conversation && @conversation.id == c.id, do: "bordered", else: "base"}
              >
                <div class="flex items-center justify-between gap-2">
                  <p class="truncate font-medium">{other_name(c, @current_user)}</p>
                  <.badge
                    :if={Conversation.unread_for?(c, @current_user.id)}
                    color="danger"
                    size="extra_small"
                    rounded="full"
                    variant="default"
                  >
                    {gettext("new")}
                  </.badge>
                </div>
                <p class="truncate text-xs opacity-70">{c.lot.title}</p>
              </.card>
            </.link>
            <.empty_state
              :if={@conversations == []}
              title={gettext("No messages yet")}
              icon="hero-chat-bubble-left-right"
            >
              {gettext("Open an offer and tap “Message the lessor”.")}
            </.empty_state>
          </div>
        </aside>

        <section :if={@conversation} class="flex min-h-[60vh] flex-col">
          <div class="mb-3 flex items-center gap-2">
            <.back_button patch={~p"/messages"} label={gettext("Messages")} class="md:hidden" />
            <div>
              <p class="font-semibold">{other_name(@conversation, @current_user)}</p>
              <.link
                navigate={~p"/lots/#{@conversation.lot_id}"}
                class="text-sm opacity-70 hover:underline"
              >
                {@conversation.lot.title}
              </.link>
            </div>
          </div>

          <div
            id="chat-log"
            phx-hook="ChatScroll"
            class="flex-1 space-y-3 overflow-y-auto rounded-xl border border-zinc-200 p-3 dark:border-zinc-800"
            style="max-height: 60vh"
          >
            <%= for m <- @messages do %>
              <%= if m.sender_id == @current_user.id do %>
                <.chat position="flipped" color="primary" size="small">
                  <.chat_section>
                    <span class="whitespace-pre-line">{m.body}</span>
                    <:status
                      time={time(m.inserted_at)}
                      deliver={if m.channel == :telegram, do: "Telegram"}
                    />
                  </.chat_section>
                </.chat>
              <% else %>
                <.chat size="small">
                  <.chat_section>
                    <span class="whitespace-pre-line">{m.body}</span>
                    <:status
                      time={time(m.inserted_at)}
                      deliver={if m.channel == :telegram, do: "Telegram"}
                    />
                  </.chat_section>
                </.chat>
              <% end %>
            <% end %>
            <p :if={@messages == []} class="py-8 text-center text-sm opacity-60">
              {gettext("Say hello and ask anything about the offer.")}
            </p>
          </div>

          <form
            id="message-form"
            phx-submit="send"
            phx-hook="Composer"
            class="mt-3 flex items-end gap-2"
          >
            <div class="flex min-h-11 flex-1 items-center rounded-3xl border border-zinc-200 bg-white px-4 py-2 focus-within:border-primary-light dark:border-zinc-700 dark:bg-zinc-900 dark:focus-within:border-primary-dark">
              <textarea
                id={"message-body-#{@sent}"}
                name="body"
                rows="1"
                maxlength="4000"
                placeholder={gettext("Write a message…")}
                aria-label={gettext("Write a message…")}
                data-composer-input
                class="block max-h-36 w-full resize-none border-0 bg-transparent p-0 text-[15px] leading-6 outline-none placeholder:text-zinc-400 focus:ring-0"
              ></textarea>
            </div>
            <button
              type="submit"
              data-composer-send
              aria-label={gettext("Send")}
              title={gettext("Send")}
              class="basa-round-btn flex size-11 shrink-0 cursor-pointer items-center justify-center rounded-full shadow-sm transition active:scale-95 disabled:cursor-default disabled:active:scale-100"
            >
              <.brand_icon name="right" class="size-5 translate-x-px" />
            </button>
          </form>
        </section>
      </div>
    </Layouts.app>
    """
  end
end
