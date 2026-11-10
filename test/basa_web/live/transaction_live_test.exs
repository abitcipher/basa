defmodule BasaWeb.TransactionLiveTest do
  use BasaWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Basa.Fixtures
  require Ash.Query

  alias Basa.Witness
  alias Basa.Witness.{AccessLog, Crypto}

  setup %{conn: conn} do
    lessor = user(%{display_name: "Olena", locale: :en})
    lessee = user(%{display_name: "Max", locale: :en})

    lot =
      published_lot(lessor, basket(lessor, [item(lessor)]), room(lessor), %{
        title: "Vocal session"
      })

    starts = hours_from_now(30)

    {:ok, booking} =
      Basa.Bookings.book(
        %{lot_id: lot.id, starts_at: starts, ends_at: DateTime.add(starts, 3600)},
        actor: lessee
      )

    %{
      lessor: lessor,
      lessee: lessee,
      booking: booking,
      lessor_conn: sign_in(conn, lessor),
      lessee_conn: sign_in(Phoenix.ConnTest.build_conn(), lessee)
    }
  end

  defp connect_device(view) do
    {:ok, {private, public}} = Crypto.signing_keypair()
    render_hook(view, "device:status", %{"supported" => true, "public_key" => nil})
    {_, box_public} = Crypto.recovery_keypair()

    render_hook(view, "device:register", %{
      "public_key" => Base.encode64(public),
      "box_key" => Base.encode64(box_public)
    })

    private
  end

  defp sign(view, private) do
    view |> element("#sign") |> render_click()
    assert_push_event(view, "device:sign", %{message: message})
    {:ok, signature} = Basa.Witness.Native.sign(private, Base.decode64!(message))
    render_hook(view, "device:signature", %{"signature" => Base.encode64(signature)})
  end

  test "both parties fill in, sign on their devices, and the contract is sealed", ctx do
    {:ok, bookings, _} = live(ctx.lessee_conn, ~p"/bookings")

    {:error, {:live_redirect, %{to: "/transactions/" <> id}}} =
      bookings |> element("#contract-#{ctx.booking.id}") |> render_click()

    {:ok, lessee_view, html} = live(ctx.lessee_conn, ~p"/transactions/#{id}")
    {:ok, lessor_view, _} = live(ctx.lessor_conn, ~p"/transactions/#{id}")
    assert html =~ "Contract No."

    lessee_view |> form("#legal-name-form", legal_name: "Maxim Berg") |> render_submit()
    lessor_view |> form("#legal-name-form", legal_name: "Olena Kovalenko") |> render_submit()
    lessor_view |> form("#terms-form", deposit: "500", claims_window_days: "5") |> render_submit()
    lessee_view |> form("#consumer-form", consumer: "true") |> render_change()

    assert render(lessee_view) =~ "Olena Kovalenko"
    assert render(lessor_view) =~ "acts as a private person"

    lessee_key = connect_device(lessee_view)
    lessor_key = connect_device(lessor_view)
    assert render(lessee_view) =~ "This device is connected"

    photo =
      file_input(lessor_view, "#photos-upload", :photos, [
        %{name: "front.jpg", content: "the microphone, front", type: "image/jpeg"}
      ])

    render_upload(photo, "front.jpg")
    assert has_element?(lessor_view, "#evidence-0", "Photo 1")

    lessor_view |> element("#prepare") |> render_click()
    assert render(lessee_view) =~ "Read and sign"
    assert has_element?(lessee_view, "#evidence-1", "Contract 2")

    sign(lessor_view, lessor_key)
    assert render(lessor_view) =~ "Waiting for the other party"

    sign(lessee_view, lessee_key)
    html = render(lessee_view)
    assert html =~ "Signed by both parties"

    tx = Witness.get_transaction!(id, authorize?: false)
    assert tx.status == :sealed and tx.deposit_amount == Decimal.new(500) and tx.consumer
    assert html =~ Crypto.to_text(tx.basa_hash)
  end

  defp sealed(ctx) do
    {:ok, tx} = Witness.open_transaction(ctx.booking.id, %{}, actor: ctx.lessee)
    {:ok, tx} = Witness.update_terms(tx, %{deposit_amount: Decimal.new(800)}, actor: ctx.lessor)

    keys =
      for user <- [ctx.lessor, ctx.lessee], into: %{} do
        {:ok, {private, public}} = Crypto.signing_keypair()

        p =
          Basa.Witness.Party
          |> Ash.Query.filter(transaction_id == ^tx.id and user_id == ^user.id)
          |> Ash.read_one!(authorize?: false)

        p = Witness.set_legal_name!(p, user.display_name, actor: user)
        Witness.register_device!(p, public, elem(Crypto.recovery_keypair(), 1), actor: user)
        {user.id, {private, public}}
      end

    {:ok, _} = Basa.Witness.Store.add(tx, :photo, "image/jpeg", "handed over", ctx.lessor)
    {:ok, tx} = Witness.prepare_transaction(tx, actor: ctx.lessor)

    tx =
      Enum.reduce([ctx.lessor, ctx.lessee], tx, fn u, tx ->
        {:ok, sig} = Crypto.sign_seal(elem(keys[u.id], 0), tx.basa_hash)
        Witness.sign_transaction!(tx, sig, actor: u)
      end)

    {tx, keys}
  end

  defp device_signs(view, {private, public}) do
    render_hook(view, "device:status", %{
      "supported" => true,
      "public_key" => Base.encode64(public)
    })

    assert_push_event(view, "device:sign", %{message: message, for: for_id})
    {:ok, signature} = Basa.Witness.Native.sign(private, Base.decode64!(message))

    render_hook(view, "device:signature", %{
      "signature" => Base.encode64(signature),
      "for" => for_id
    })
  end

  test "after sealing: the lessee returns with photos, the lessor accepts", ctx do
    {tx, keys} = sealed(ctx)
    {:ok, lessee_view, _} = live(ctx.lessee_conn, ~p"/transactions/#{tx.id}")
    {:ok, lessor_view, _} = live(ctx.lessor_conn, ~p"/transactions/#{tx.id}")

    render_hook(lessee_view, "device:status", %{
      "supported" => true,
      "public_key" => Base.encode64(elem(keys[ctx.lessee.id], 1))
    })

    lessee_view |> element("#start-return") |> render_click()

    photo =
      file_input(lessee_view, "#act-form", :act_photos, [
        %{name: "back.jpg", content: "handed back, fine", type: "image/jpeg"}
      ])

    render_upload(photo, "back.jpg")
    lessee_view |> form("#act-form", terms: %{note: "All in order"}) |> render_submit()
    device_signs(lessee_view, keys[ctx.lessee.id])

    assert Witness.get_transaction!(tx.id, authorize?: false).status == :returned
    assert render(lessor_view) =~ "All in order"
    assert has_element?(lessor_view, "#act-1")

    act = hd(Basa.Witness.Acts.chain(tx))

    assert ctx.lessor_conn
           |> get(~p"/transactions/#{tx.id}/acts/#{act.id}/files/0")
           |> response(200) ==
             "handed back, fine"

    render_hook(lessor_view, "device:status", %{
      "supported" => true,
      "public_key" => Base.encode64(elem(keys[ctx.lessor.id], 1))
    })

    lessor_view |> element("#start-acceptance") |> render_click()
    lessor_view |> form("#act-form") |> render_submit()
    device_signs(lessor_view, keys[ctx.lessor.id])

    tx = Witness.get_transaction!(tx.id, authorize?: false)
    assert {tx.status, tx.deposit_status} == {:closed, :released}
    assert render(lessee_view) =~ "returned to the lessee"
  end

  test "evidence downloads: the parties only, every one logged", ctx do
    {:ok, tx} = Witness.open_transaction(ctx.booking.id, %{}, actor: ctx.lessee)
    {:ok, _} = Basa.Witness.Store.add(tx, :photo, "image/jpeg", "a photo", ctx.lessee)
    path = ~p"/transactions/#{tx.id}/evidence/0"

    assert ctx.lessor_conn |> get(path) |> response(200) == "a photo"
    assert get(sign_in(Phoenix.ConnTest.build_conn(), user()), path) |> response(404)

    assert get(sign_in(Phoenix.ConnTest.build_conn(), user(%{role: :admin})), path)
           |> response(404)

    assert Phoenix.ConnTest.build_conn() |> get(path) |> response(404)

    assert [%{action: :open, actor_id: actor_id}] =
             AccessLog
             |> Ash.Query.filter(transaction_id == ^tx.id)
             |> Ash.read!(authorize?: false)

    assert actor_id == ctx.lessor.id
  end

  test "someone outside the booking is sent away", ctx do
    {:ok, tx} = Witness.open_transaction(ctx.booking.id, %{}, actor: ctx.lessee)

    assert {:error, {:live_redirect, %{to: "/bookings"}}} =
             live(sign_in(Phoenix.ConnTest.build_conn(), user()), ~p"/transactions/#{tx.id}")
  end
end
