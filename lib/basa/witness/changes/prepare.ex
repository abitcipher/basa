defmodule Basa.Witness.Changes.Prepare do
  use Ash.Resource.Change

  require Ash.Query

  alias Basa.Witness.{Contract, Evidence, Manifest, Party}

  @impl true
  def change(changeset, _opts, context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      tx = changeset.data

      parties =
        Party |> Ash.Query.filter(transaction_id == ^tx.id) |> Ash.read!(authorize?: false)

      photos =
        Evidence
        |> Ash.Query.filter(transaction_id == ^tx.id and kind == :photo and is_nil(act_id))
        |> Ash.count!(authorize?: false)

      cond do
        Enum.any?(parties, &(&1.legal_name in [nil, ""])) ->
          Ash.Changeset.add_error(changeset, "both parties need to give their legal names")

        Enum.any?(parties, &(is_nil(&1.public_key) or is_nil(&1.box_key))) ->
          Ash.Changeset.add_error(
            changeset,
            "both parties need to connect the device they sign on"
          )

        photos == 0 ->
          Ash.Changeset.add_error(changeset, "add at least one photo of the condition")

        true ->
          with {:ok, _} <- Contract.attach(tx, context.actor),
               {:ok, manifest, hash} <- Manifest.build(tx) do
            changeset
            |> Ash.Changeset.force_change_attribute(:manifest, manifest)
            |> Ash.Changeset.force_change_attribute(:basa_hash, hash)
            |> Ash.Changeset.force_change_attribute(:status, :signing)
          else
            {:error, reason} -> Ash.Changeset.add_error(changeset, inspect(reason))
          end
      end
    end)
  end
end
