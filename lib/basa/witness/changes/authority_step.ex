defmodule Basa.Witness.Changes.AuthorityStep do
  use Ash.Resource.Change

  alias Basa.Witness.AccessLog

  @impl true
  def change(changeset, opts, context) do
    step = opts[:step]

    changeset =
      if step in [:approved, :notified] and notify?(changeset, step),
        do:
          Ash.Changeset.force_change_attribute(
            changeset,
            :parties_notified_at,
            DateTime.utc_now()
          ),
        else: changeset

    Ash.Changeset.after_action(changeset, fn _changeset, request ->
      Ash.create!(
        AccessLog,
        %{
          transaction_id: request.transaction_id,
          action: if(step in [:exported, :opened], do: :recovery, else: :request),
          actor_id: context.actor && context.actor.id,
          reason: reason(step, request),
          reference: request.reference,
          result: "ok"
        },
        action: :record,
        authorize?: false
      )

      if request.parties_notified_at && step in [:approved, :notified] do
        Basa.Witness.AuthorityNotifyWorker.notify(request)
      end

      Phoenix.PubSub.broadcast(Basa.PubSub, "witness:#{request.transaction_id}", :witness_changed)

      {:ok, request}
    end)
  end

  defp notify?(_changeset, :notified), do: true
  defp notify?(changeset, :approved), do: Ash.Changeset.get_attribute(changeset, :notify_parties)

  defp reason(:filed, r), do: "authority request filed: #{r.authority} (#{r.basis})"

  defp reason(:approved, r) do
    "authority request approved" <>
      if(r.parties_notified_at,
        do: ", parties told",
        else: ", notice withheld: #{r.no_notice_reason}"
      )
  end

  defp reason(:rejected, r), do: "authority request rejected: #{r.decision_note}"
  defp reason(:notified, _r), do: "parties told of the authority request"
  defp reason(:exported, _r), do: "recovery kit exported (sealed data) for the key holders"

  defp reason(:opened, r),
    do: "opened offline by #{r.key_holders}; handed over to #{r.handed_over_to}"
end
