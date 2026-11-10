defmodule Basa.Witness.Changes.Open do
  use Ash.Resource.Change

  alias Basa.Witness.Crypto

  @impl true
  def change(changeset, _opts, _context) do
    booking_id = Ash.Changeset.get_attribute(changeset, :booking_id)

    case Ash.get(Basa.Bookings.Booking, booking_id,
           load: [lessee: [:locale], lot: [owner: [:locale], room: [:geo_city]]],
           authorize?: false
         ) do
      {:ok, %{status: status}} when status != :confirmed ->
        Ash.Changeset.add_error(changeset, "the booking must be confirmed first")

      {:ok, booking} ->
        changeset
        |> Ash.Changeset.force_change_attribute(:storage_mode, Basa.Witness.storage_mode())
        |> defaults(booking)
        |> Ash.Changeset.put_context(:witness_open, %{
          offeror_id: booking.lot.owner_id,
          acceptor_id: booking.lessee_id
        })
        |> Ash.Changeset.before_action(&new_key/1)
        |> Ash.Changeset.after_action(&store_shares_and_parties/2)

      {:error, error} ->
        Ash.Changeset.add_error(changeset, error)
    end
  end

  defp new_key(changeset) do
    id = Ash.Changeset.get_attribute(changeset, :id)

    with public when is_binary(public) <- Basa.Witness.recovery_public_key(),
         {:ok, key} <- Crypto.new_key(id, public) do
      changeset
      |> Ash.Changeset.force_change_attribute(:recovery_sealed, key.recovery)
      |> Ash.Changeset.put_context(
        :witness_open,
        Map.put(changeset.context.witness_open, :shares, key.shares)
      )
    else
      nil -> Ash.Changeset.add_error(changeset, "no recovery public key configured")
      {:error, error} -> Ash.Changeset.add_error(changeset, error)
    end
  end

  defp defaults(changeset, booking) do
    jurisdiction =
      Ash.Changeset.get_attribute(changeset, :jurisdiction) ||
        if(booking.lot.room.geo_city && booking.lot.room.geo_city.country_code == "UA",
          do: :ua,
          else: :eu
        )

    type = booking.lot.deal
    languages = Enum.uniq([booking.lot.owner.locale, booking.lessee.locale])

    changeset
    |> Ash.Changeset.force_change_attribute(:contract_type, type)
    |> then(fn cs ->
      given? =
        Enum.any?([:claims_window_days, "claims_window_days"], &Map.has_key?(cs.params, &1))

      if type == :sale and not given?,
        do: Ash.Changeset.force_change_attribute(cs, :claims_window_days, 14),
        else: cs
    end)
    |> Ash.Changeset.force_change_attribute(:jurisdiction, jurisdiction)
    |> Ash.Changeset.force_change_attribute(:languages, languages)
    |> then(fn cs ->
      if Ash.Changeset.get_attribute(cs, :template),
        do: cs,
        else: Ash.Changeset.force_change_attribute(cs, :template, "#{type}-#{jurisdiction}@1")
    end)
  end

  defp store_shares_and_parties(changeset, transaction) do
    %{shares: shares, offeror_id: offeror_id, acceptor_id: acceptor_id} =
      changeset.context.witness_open

    for {owner, share} <- shares do
      Ash.create!(
        Basa.Witness.KeyShare,
        %{owner: owner, share: share, transaction_id: transaction.id},
        action: :store,
        authorize?: false
      )
    end

    for {role, user_id} <- [offeror: offeror_id, acceptor: acceptor_id] do
      Ash.create!(
        Basa.Witness.Party,
        %{role: role, user_id: user_id, transaction_id: transaction.id},
        action: :add,
        authorize?: false
      )
    end

    {:ok, transaction}
  end
end
