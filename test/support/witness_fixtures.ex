defmodule Basa.WitnessFixtures do
  import Basa.Fixtures
  require Ash.Query

  alias Basa.Witness
  alias Basa.Witness.{Crypto, Party, Store}

  def sealed_contract(opts \\ []) do
    lessor = opts[:lessor] || user(%{display_name: "Olena"})
    lessee = opts[:lessee] || user(%{display_name: "Max"})

    lot =
      published_lot(lessor, basket(lessor, [item(lessor)]), room(lessor), %{
        title: "Vocal session",
        deal: opts[:deal] || :lease
      })

    starts = hours_from_now(opts[:hours] || 30)

    {:ok, booking} =
      Basa.Bookings.book(
        %{lot_id: lot.id, starts_at: starts, ends_at: DateTime.add(starts, 3600)},
        actor: lessee
      )

    {:ok, tx} =
      with_mode(opts[:storage_mode], fn ->
        Witness.open_transaction(booking.id, %{}, actor: lessee)
      end)

    devices =
      for user <- [lessor, lessee], into: %{} do
        {:ok, {private, public}} = Crypto.signing_keypair()
        {box_private, box_public} = Crypto.recovery_keypair()

        p =
          Party
          |> Ash.Query.filter(transaction_id == ^tx.id and user_id == ^user.id)
          |> Ash.read_one!(authorize?: false)

        p = Witness.set_legal_name!(p, user.display_name, actor: user)
        Witness.register_device!(p, public, box_public, actor: user)
        {user.id, {private, box_private}}
      end

    keys = Map.new(devices, fn {id, {k, _}} -> {id, k} end)
    box_keys = Map.new(devices, fn {id, {_, b}} -> {id, b} end)

    for photo <- opts[:photos] || ["handed over: perfect"] do
      {:ok, _} = Store.add(tx, :photo, "image/jpeg", photo, lessor)
    end

    {:ok, tx} = Witness.prepare_transaction(tx, actor: lessor)

    tx =
      Enum.reduce([lessor, lessee], tx, fn user, tx ->
        {:ok, sig} = Crypto.sign_seal(keys[user.id], tx.basa_hash)
        Witness.sign_transaction!(tx, sig, actor: user)
      end)

    %{tx: tx, lessor: lessor, lessee: lessee, booking: booking, keys: keys, box_keys: box_keys}
  end

  defp with_mode(nil, fun), do: fun.()

  defp with_mode(mode, fun) do
    before = Basa.Witness.config()
    Application.put_env(:basa, Basa.Witness, Keyword.put(before, :storage_mode, mode))

    try do
      fun.()
    after
      Application.put_env(:basa, Basa.Witness, before)
    end
  end
end
