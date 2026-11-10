defmodule Basa.Bookings.BookingTest do
  use Basa.DataCase, async: true

  import Basa.Fixtures
  alias Basa.{Bookings, Catalog}

  setup do
    lessor = user()
    lessee = user()
    mic = item(lessor, %{title: "Neumann U87"})
    room = room(lessor)
    lot = published_lot(lessor, basket(lessor, [mic]), room)
    %{lessor: lessor, lessee: lessee, mic: mic, room: room, lot: lot}
  end

  defp book(lot, actor, from_h, to_h) do
    Bookings.book(
      %{lot_id: lot.id, starts_at: hours_from_now(from_h), ends_at: hours_from_now(to_h)},
      actor: actor
    )
  end

  test "an instant lot confirms at once and is priced per hour", %{lot: lot, lessee: lessee} do
    assert {:ok, booking} = book(lot, lessee, 24, 27)
    assert booking.status == :confirmed
    assert booking.units == 3
    assert Decimal.equal?(booking.price_amount, 1500)
  end

  test "first come, first served: an overlapping booking fails", %{lot: lot, lessee: lessee} do
    assert {:ok, _} = book(lot, lessee, 24, 27)
    assert {:error, error} = book(lot, user(), 26, 28)
    assert Exception.message(error) =~ "this slot was just taken"
  end

  test "back-to-back bookings are allowed", %{lot: lot, lessee: lessee} do
    assert {:ok, _} = book(lot, lessee, 24, 26)
    assert {:ok, _} = book(lot, user(), 26, 28)
  end

  test "a shared item is blocked in the owner's other lots only for the booked slot", ctx do
    %{lessor: lessor, mic: mic, lessee: lessee, lot: lot} = ctx
    other_room = room(lessor, %{title: "Mobile rig", mobile: true, service_radius_km: 30})
    other_lot = published_lot(lessor, basket(lessor, [mic], %{title: "Mic only"}), other_room)

    assert {:ok, _} = book(lot, lessee, 24, 27)

    assert {:error, _} = book(other_lot, user(), 25, 26)
    assert {:ok, _} = book(other_lot, user(), 30, 31)
  end

  test "cancelling frees the slot everywhere", %{lot: lot, lessee: lessee} do
    {:ok, booking} = book(lot, lessee, 48, 50)
    assert {:ok, %{status: :cancelled}} = Bookings.cancel_booking(booking, actor: lessee)
    assert {:ok, _} = book(lot, user(), 48, 50)
  end

  test "buffer time blocks the minutes after a booking", ctx do
    %{lessor: lessor, room: room} = ctx
    lot = published_lot(lessor, basket(lessor, [item(lessor)]), room, %{buffer_minutes: 30})
    assert {:ok, _} = book(lot, ctx.lessee, 24, 25)
    assert {:error, _} = book(lot, user(), 25, 26)
  end

  test "request lots wait for the lessor but hold the slot", ctx do
    %{lessor: lessor, room: room, lessee: lessee} = ctx
    lot = published_lot(lessor, basket(lessor, [item(lessor)]), room, %{booking_mode: :request})

    assert {:ok, %{status: :pending} = booking} = book(lot, lessee, 24, 25)
    assert {:error, _} = book(lot, user(), 24, 25)

    assert {:error, %Ash.Error.Forbidden{}} = Bookings.confirm_booking(booking, actor: lessee)
    assert {:ok, %{status: :confirmed}} = Bookings.confirm_booking(booking, actor: lessor)
  end

  test "lessors can't book their own lot", %{lot: lot, lessor: lessor} do
    assert {:error, error} = book(lot, lessor, 24, 25)
    assert Exception.message(error) =~ "your own offer"
  end

  test "unpublished lots can't be booked", ctx do
    draft = lot(ctx.lessor, basket(ctx.lessor, [item(ctx.lessor)]), ctx.room)
    assert {:error, error} = book(draft, ctx.lessee, 24, 25)
    assert Exception.message(error) =~ "not available"
  end

  test "opening hours are enforced", ctx do
    hours = Map.new(1..7, &{to_string(&1), [["09:00", "18:00"]]})

    lot =
      published_lot(ctx.lessor, basket(ctx.lessor, [item(ctx.lessor)]), ctx.room, %{
        weekly_hours: hours
      })

    tomorrow = Date.utc_today() |> Date.add(1)
    at = fn h -> DateTime.new!(tomorrow, Time.new!(h, 0, 0), "Etc/UTC") end

    assert {:error, error} =
             Bookings.book(%{lot_id: lot.id, starts_at: at.(19), ends_at: at.(20)},
               actor: ctx.lessee
             )

    assert Exception.message(error) =~ "outside the opening hours"

    assert {:ok, _} =
             Bookings.book(%{lot_id: lot.id, starts_at: at.(10), ends_at: at.(12)},
               actor: ctx.lessee
             )
  end

  test "bookings are visible to both parties only", %{lot: lot, lessee: lessee, lessor: lessor} do
    {:ok, booking} = book(lot, lessee, 24, 25)
    assert {:ok, _} = Bookings.get_booking(booking.id, actor: lessor)
    assert {:ok, _} = Bookings.get_booking(booking.id, actor: lessee)
    assert {:error, _} = Bookings.get_booking(booking.id, actor: user())
  end

  test "completing a booking records the activity", %{lot: lot, lessee: lessee, lessor: lessor} do
    {:ok, booking} = book(lot, lessee, 24, 25)

    assert {:ok, %{status: :completed, completed_at: %DateTime{}}} =
             Bookings.complete_booking(booking, actor: lessor)

    assert Catalog.get_lot!(lot.id, actor: lessee).state == :published
  end
end
