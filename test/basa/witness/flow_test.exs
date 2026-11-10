defmodule Basa.Witness.FlowTest do
  use Basa.DataCase, async: true
  use Oban.Testing, repo: Basa.Repo

  import Basa.Fixtures
  require Ash.Query

  alias Basa.Witness
  alias Basa.Witness.{Crypto, Evidence, Party, Store, Verify}

  setup do
    lessor = user(%{display_name: "Olena", locale: :uk})
    lessee = user(%{display_name: "Max", locale: :en})

    lot =
      published_lot(lessor, basket(lessor, [item(lessor)]), room(lessor), %{
        title: "Vocal session",
        booking_mode: :request
      })

    starts = hours_from_now(30)

    {:ok, booking} =
      Basa.Bookings.book(
        %{lot_id: lot.id, starts_at: starts, ends_at: DateTime.add(starts, 3600)},
        actor: lessee
      )

    %{lessor: lessor, lessee: lessee, booking: booking}
  end

  defp party(tx, user),
    do:
      Party
      |> Ash.Query.filter(transaction_id == ^tx.id and user_id == ^user.id)
      |> Ash.read_one!(authorize?: false)

  defp reload(tx), do: Witness.get_transaction!(tx.id, authorize?: false)

  defp ready_parties(tx, lessor, lessee) do
    for {user, name} <- [{lessor, "Olena Kovalenko"}, {lessee, "Maxim Berg"}], into: %{} do
      {:ok, {private, public}} = Crypto.signing_keypair()
      p = party(tx, user)
      Witness.set_legal_name!(p, name, actor: user)

      Witness.register_device!(party(tx, user), public, elem(Crypto.recovery_keypair(), 1),
        actor: user
      )

      {user.id, private}
    end
  end

  test "the whole flow: open, terms, evidence, prepare, sign twice, sealed", ctx do
    %{lessor: lessor, lessee: lessee} = ctx

    assert {:error, _} = Witness.open_transaction(ctx.booking.id, %{}, actor: lessee)
    booking = Basa.Bookings.confirm_booking!(ctx.booking, actor: lessor)

    assert {:error, %Ash.Error.Forbidden{}} =
             Witness.open_transaction(booking.id, %{}, actor: user())

    assert {:ok, tx} = Witness.open_transaction(booking.id, %{}, actor: lessee)

    assert {:ok, tx} =
             Witness.update_terms(tx, %{deposit_amount: Decimal.new(500)}, actor: lessor)

    assert {:error, %Ash.Error.Forbidden{}} =
             Witness.update_terms(tx, %{claims_window_days: 1}, actor: lessee)

    assert {:ok, tx} = Witness.declare_consumer(tx, true, actor: lessee)
    assert {:error, %Ash.Error.Forbidden{}} = Witness.declare_consumer(tx, false, actor: lessor)

    assert {:error, %Ash.Error.Forbidden{}} =
             Witness.set_legal_name(party(tx, lessee), "Someone else", actor: lessor)

    keys = ready_parties(tx, lessor, lessee)

    assert {:error, error} = Witness.prepare_transaction(tx, actor: lessor)
    assert Exception.message(error) =~ "photo"
    {:ok, _} = Store.add(tx, :photo, "image/jpeg", "the microphone, front", lessor)

    assert {:ok, tx} = Witness.prepare_transaction(tx, actor: lessor)
    assert tx.status == :signing and byte_size(tx.basa_hash) == 32

    evidence =
      Evidence
      |> Ash.Query.filter(transaction_id == ^tx.id)
      |> Ash.Query.sort(position: :asc)
      |> Ash.read!(authorize?: false)

    assert Enum.map(evidence, & &1.kind) == [:photo, :contract]
    assert Verify.transaction(tx).ok?

    assert Store.add(tx, :photo, "image/jpeg", "another", lessor) == {:error, :not_a_draft}
    assert {:error, _} = Witness.set_legal_name(party(tx, lessor), "Changed", actor: lessor)

    {:ok, {other, _}} = Crypto.signing_keypair()
    {:ok, forged} = Crypto.sign_seal(other, tx.basa_hash)
    assert {:error, error} = Witness.sign_transaction(tx, forged, actor: lessee)
    assert Exception.message(error) =~ "does not match"

    {:ok, sig} = Crypto.sign_seal(keys[lessor.id], tx.basa_hash)
    assert {:ok, tx} = Witness.sign_transaction(tx, sig, actor: lessor)
    assert tx.status == :signing
    assert {:error, _} = Witness.sign_transaction(tx, sig, actor: lessor)

    {:ok, sig} = Crypto.sign_seal(keys[lessee.id], tx.basa_hash)
    assert {:ok, tx} = Witness.sign_transaction(tx, sig, actor: lessee)
    assert tx.status == :sealed and tx.sealed_at

    assert {{:timestamp, :pending}} =
             {List.keyfind(Verify.transaction(reload(tx)).checks, :timestamp, 0)}

    assert_enqueued(worker: Basa.Witness.TimestampWorker, args: %{transaction_id: tx.id})
    assert %{failure: 0} = Oban.drain_queue(queue: :default)

    result = Verify.transaction(reload(tx))
    assert result.ok?
    assert {:timestamp, :ok} in result.checks
    assert {{:signature, :offeror}, :ok} in result.checks

    assert {:error, _} = Witness.cancel_transaction(tx, actor: lessee)
  end

  test "either party can cancel a draft", ctx do
    booking = Basa.Bookings.confirm_booking!(ctx.booking, actor: ctx.lessor)
    {:ok, tx} = Witness.open_transaction(booking.id, %{}, actor: ctx.lessor)
    assert {:ok, %{status: :cancelled}} = Witness.cancel_transaction(tx, actor: ctx.lessee)
  end
end
