defmodule BasaWeb.RpcControllerTest do
  use BasaWeb.ConnCase, async: true
  import Basa.Fixtures

  setup do
    lessor = user()
    room = room(lessor)
    basket = basket(lessor, [item(lessor)])

    %{
      lessor: lessor,
      lot: published_lot(lessor, basket, room, %{timezone: "Europe/Kyiv"}),
      room: room,
      basket: basket
    }
  end

  defp rpc(conn, lot_id, from) do
    conn
    |> put_req_header("content-type", "application/json")
    |> put_req_header("accept", "application/json")
    |> post(~p"/rpc/run", %{
      action: "lot_availability",
      input: %{lotId: lot_id, from: Date.to_iso8601(from), days: 3},
      fields: ["date", "free", "total", %{slots: ["startsAt", "endsAt", "free"]}]
    })
    |> json_response(200)
  end

  test "free slots per day, camelCase, for anyone", %{conn: conn, lot: lot} do
    tomorrow = DateTime.now!("Europe/Kyiv") |> DateTime.to_date() |> Date.add(1)

    assert %{"success" => true, "data" => [day | _] = days} = rpc(conn, lot.id, tomorrow)
    assert length(days) == 3
    assert day["date"] == Date.to_iso8601(tomorrow)
    assert day["total"] > 0 and day["free"] == day["total"]
    assert [%{"startsAt" => _, "endsAt" => _, "free" => true} | _] = day["slots"]
  end

  test "a booked slot shows as taken", %{conn: conn, lot: lot} do
    tomorrow = DateTime.now!("Europe/Kyiv") |> DateTime.to_date() |> Date.add(1)

    starts =
      DateTime.new!(tomorrow, ~T[12:00:00], "Europe/Kyiv") |> DateTime.shift_zone!("Etc/UTC")

    {:ok, _} =
      Basa.Bookings.book(
        %{lot_id: lot.id, starts_at: starts, ends_at: DateTime.add(starts, 3600)},
        actor: user()
      )

    %{"data" => [day | _]} = rpc(conn, lot.id, tomorrow)
    assert day["free"] == day["total"] - 1

    {:ok, starts_iso, _} =
      DateTime.from_iso8601(Enum.find(day["slots"], &(!&1["free"]))["startsAt"])

    assert DateTime.compare(starts_iso, starts) == :eq
  end

  test "drafts answer only their owner (Ash policies apply)", ctx do
    draft = lot(ctx.lessor, ctx.basket, ctx.room)
    today = Date.utc_today()

    assert %{"success" => false} = rpc(ctx.conn, draft.id, today)
    assert %{"success" => true} = ctx.conn |> sign_in(ctx.lessor) |> rpc(draft.id, today)
  end

  test "a lessor's schedule over RPC, only when signed in", ctx do
    body = %{
      action: "lessor_schedule",
      input: %{
        from: Date.to_iso8601(Date.utc_today()),
        to: Date.to_iso8601(Date.add(Date.utc_today(), 7))
      },
      fields: ["id", "lotTitle", "status"]
    }

    post_json = fn conn ->
      conn
      |> put_req_header("content-type", "application/json")
      |> put_req_header("accept", "application/json")
      |> post(~p"/rpc/run", body)
      |> json_response(200)
    end

    assert %{"success" => false} = post_json.(ctx.conn)
    assert %{"success" => true, "data" => []} = ctx.conn |> sign_in(ctx.lessor) |> then(post_json)
  end

  test "the generated TypeScript is up to date" do
    Mix.Task.rerun("ash_typescript.codegen", ["--check"])
  end
end
