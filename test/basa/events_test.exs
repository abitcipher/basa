defmodule Basa.EventsTest do
  use Basa.DataCase, async: false
  use Oban.Testing, repo: Basa.Repo

  import Basa.Fixtures

  @url "amqp://basa:basa@localhost:5672"

  setup do
    previous = Application.get_env(:basa, :external_publisher)
    Application.put_env(:basa, :external_publisher, Basa.Events.RabbitPublisher)
    on_exit(fn -> Application.put_env(:basa, :external_publisher, previous) end)
    :ok
  end

  defp hours(h),
    do:
      DateTime.utc_now()
      |> DateTime.add(h * 3600, :second)
      |> Map.merge(%{minute: 0, second: 0, microsecond: {0, 6}})

  test "domain changes become outbox jobs with typed envelopes" do
    lessor = user()
    lot = published_lot(lessor, basket(lessor, [item(lessor)]), room(lessor))

    {:ok, booking} =
      Basa.Bookings.book(%{lot_id: lot.id, starts_at: hours(24), ends_at: hours(26)},
        actor: user()
      )

    Basa.Bookings.cancel_booking!(booking, actor: lessor)

    types =
      all_enqueued(worker: Basa.Events.PublishWorker)
      |> Enum.map(& &1.args["type"])

    assert "lot.draft" in types
    assert "lot.published" in types
    assert "booking.confirmed" in types
    assert "booking.cancelled" in types
    assert "availability.changed" in types

    [job] =
      all_enqueued(worker: Basa.Events.PublishWorker)
      |> Enum.filter(&(&1.args["type"] == "booking.confirmed"))

    assert %{
             "id" => _,
             "occurred_at" => _,
             "data" => %{"booking_id" => id, "price_amount" => "1000"}
           } = job.args

    assert id == booking.id
    refute Map.has_key?(job.args["data"], "email")
  end

  describe "with RabbitMQ" do
    setup do
      case AMQP.Connection.open(@url) do
        {:ok, conn} ->
          {:ok, chan} = AMQP.Channel.open(conn)

          :ok =
            AMQP.Exchange.declare(chan, Basa.Events.RabbitPublisher.exchange(), :topic,
              durable: true
            )

          {:ok, %{queue: queue}} = AMQP.Queue.declare(chan, "", exclusive: true)

          :ok =
            AMQP.Queue.bind(chan, queue, Basa.Events.RabbitPublisher.exchange(),
              routing_key: "booking.#"
            )

          start_supervised!({Basa.Events.RabbitPublisher, url: @url})
          wait_connected()

          on_exit(fn -> AMQP.Connection.close(conn) end)
          %{chan: chan, queue: queue}

        _ ->
          {:skip, :rabbitmq_not_running}
      end
    end

    test "a booking is published to basa.events with publisher confirms", %{
      chan: chan,
      queue: queue
    } do
      lessor = user()
      lot = published_lot(lessor, basket(lessor, [item(lessor)]), room(lessor))

      {:ok, booking} =
        Basa.Bookings.book(%{lot_id: lot.id, starts_at: hours(30), ends_at: hours(31)},
          actor: user()
        )

      assert %{success: n, failure: 0} = Oban.drain_queue(queue: :events)
      assert n >= 1

      {:ok, payload, meta} = AMQP.Basic.get(chan, queue, no_ack: true)
      assert meta.routing_key == "booking.confirmed"
      assert meta.content_type == "application/json"

      assert %{"type" => "booking.confirmed", "data" => %{"booking_id" => id}} =
               Jason.decode!(payload)

      assert id == booking.id
    end
  end

  defp wait_connected(tries \\ 50) do
    case :sys.get_state(Basa.Events.RabbitPublisher) do
      %{chan: nil} when tries > 0 -> Process.sleep(50) && wait_connected(tries - 1)
      _ -> :ok
    end
  end
end
