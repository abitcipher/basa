defmodule Basa.Events do
  @pubsub Basa.PubSub

  def availability_topic(owner_id), do: "availability:#{owner_id}"

  def availability_changed(owner_id) do
    Phoenix.PubSub.broadcast(
      @pubsub,
      availability_topic(owner_id),
      {:availability_changed, owner_id}
    )

    Basa.Events.External.publish("availability.changed", %{owner_id: owner_id})
  end

  def bookings_changed(owner_id),
    do:
      Phoenix.PubSub.broadcast(
        @pubsub,
        availability_topic(owner_id),
        {:bookings_changed, owner_id}
      )

  def subscribe_availability(owner_id),
    do: Phoenix.PubSub.subscribe(@pubsub, availability_topic(owner_id))

  def user_topic(user_id), do: "user:#{user_id}"

  def notify_user(user_id, message),
    do: Phoenix.PubSub.broadcast(@pubsub, user_topic(user_id), message)
end
