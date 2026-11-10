defmodule Basa.PaymentsTest do
  use BasaWeb.ConnCase, async: false
  use Oban.Testing, repo: Basa.Repo

  import Basa.Fixtures
  alias Basa.Payments
  alias Basa.Payments.Gateway.Fake
  alias Basa.Payments.Settle

  setup do
    Fake.start()
    lessor = user()
    lessee = user()
    lot = published_lot(lessor, basket(lessor, [item(lessor)]), room(lessor))
    %{lessor: lessor, lessee: lessee, lot: lot}
  end

  defp completed_booking(%{lot: lot, lessee: lessee, lessor: lessor}) do
    start = hours_from_now(24)

    {:ok, b} =
      Basa.Bookings.book(
        %{lot_id: lot.id, starts_at: start, ends_at: DateTime.add(start, 2 * 3600)},
        actor: lessee
      )

    Basa.Bookings.complete_booking!(b, actor: lessor)
  end

  test "payments switched off: no new checkout", ctx do
    booking = completed_booking(ctx)

    {:ok, _} =
      Basa.System.update_settings(Basa.System.settings(), %{services_off: [:payments]},
        actor: user(%{role: :admin})
      )

    refute Payments.enabled?()
    assert {:error, error} = Payments.start_commission(booking.id, 50, actor: ctx.lessor)
    assert Exception.message(error) =~ "payments are unavailable"
    refute_enqueued(worker: Basa.Payments.ReconcileWorker)
  end

  describe "voluntary commission" do
    test "the lessor of a completed booking opens a checkout", ctx do
      booking = completed_booking(ctx)
      {:ok, payment} = Payments.start_commission(booking.id, 50, actor: ctx.lessor)

      assert payment.status == :pending
      assert payment.currency == :UAH
      assert payment.payment_url =~ "https://pay.test/"
      assert_enqueued(worker: Basa.Payments.ReconcileWorker, args: %{payment_id: payment.id})
    end

    test "only for completed bookings, only by the lessor, never above the booking price", ctx do
      start = hours_from_now(30)

      {:ok, open} =
        Basa.Bookings.book(
          %{lot_id: ctx.lot.id, starts_at: start, ends_at: DateTime.add(start, 3600)},
          actor: ctx.lessee
        )

      assert {:error, _} = Payments.start_commission(open.id, 10, actor: ctx.lessor)

      done = completed_booking(ctx)
      assert {:error, _} = Payments.start_commission(done.id, 10, actor: ctx.lessee)
      assert {:error, error} = Payments.start_commission(done.id, 5000, actor: ctx.lessor)
      assert Exception.message(error) =~ "can't be more than the booking"
    end
  end

  describe "premium" do
    test "a successful payment features the lot, once", ctx do
      Application.put_env(:basa, :external_publisher, Basa.Events.RabbitPublisher)
      on_exit(fn -> Application.delete_env(:basa, :external_publisher) end)

      {:ok, payment} = Payments.start_premium(ctx.lot.id, :featured_7d, actor: ctx.lessor)
      assert Decimal.equal?(payment.amount, 199)

      Fake.set_status(payment.provider_payment_id, :succeeded)
      {:ok, paid} = Settle.refresh(payment)
      assert paid.status == :succeeded and paid.paid_at

      lot = Ash.get!(Basa.Catalog.Lot, ctx.lot.id, authorize?: false, load: [:featured])
      assert lot.featured
      first_until = lot.featured_until

      {:ok, _} = Settle.refresh(paid)

      assert Ash.get!(Basa.Catalog.Lot, ctx.lot.id, authorize?: false).featured_until ==
               first_until

      assert_enqueued(worker: Basa.Events.PublishWorker, args: %{type: "payment.succeeded"})
    end

    test "featured lots come first in search", ctx do
      owner = user()

      other =
        published_lot(owner, basket(owner, [item(owner)]), room(owner), %{title: "Newer studio"})

      assert [%{id: first} | _] = Basa.Search.find_lots(%{})
      assert first == other.id

      {:ok, p} = Payments.start_premium(ctx.lot.id, :featured_30d, actor: ctx.lessor)
      Fake.set_status(p.provider_payment_id, :succeeded)
      Settle.refresh(p)

      assert [%{id: first} | _] = Basa.Search.find_lots(%{})
      assert first == ctx.lot.id
    end

    test "a failed payment changes nothing and stays failed", ctx do
      {:ok, payment} = Payments.start_premium(ctx.lot.id, :featured_7d, actor: ctx.lessor)
      Fake.set_status(payment.provider_payment_id, :failed)
      {:ok, failed} = Settle.refresh(payment)
      assert failed.status == :failed

      Fake.set_status(payment.provider_payment_id, :succeeded)
      assert {:ok, %{status: :failed}} = Settle.refresh(failed)
      refute Ash.get!(Basa.Catalog.Lot, ctx.lot.id, authorize?: false, load: [:featured]).featured
    end

    test "nobody else can promote your lot", ctx do
      assert {:error, _} = Payments.start_premium(ctx.lot.id, :featured_7d, actor: ctx.lessee)
    end
  end

  describe "web" do
    test "the return page settles from the gateway, not from the URL", %{conn: conn} = ctx do
      {:ok, payment} = Payments.start_premium(ctx.lot.id, :featured_7d, actor: ctx.lessor)
      Fake.set_status(payment.provider_payment_id, :succeeded)

      conn = conn |> sign_in(ctx.lessor) |> get(~p"/payments/#{payment.id}/return?status=failed")
      assert redirected_to(conn) == "/my"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "featured"
    end

    test "webhooks need a valid signature", %{conn: conn} = ctx do
      {:ok, payment} = Payments.start_premium(ctx.lot.id, :featured_7d, actor: ctx.lessor)
      Fake.set_status(payment.provider_payment_id, :succeeded)

      body =
        Jason.encode!(%{
          event_type: "payment_succeeded",
          content: %{type: "payment_details", object: %{payment_id: payment.provider_payment_id}}
        })

      bad =
        build_conn()
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-webhook-signature-512", "nope")
        |> post(~p"/webhooks/hyperswitch", body)

      assert bad.status == 401
      assert Ash.get!(Payments.Payment, payment.id, authorize?: false).status == :pending

      sig = :crypto.mac(:hmac, :sha512, "test", body) |> Base.encode16(case: :lower)

      ok =
        build_conn()
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-webhook-signature-512", sig)
        |> post(~p"/webhooks/hyperswitch", body)

      assert ok.status == 200
      assert Ash.get!(Payments.Payment, payment.id, authorize?: false).status == :succeeded
      _ = conn
    end
  end
end
