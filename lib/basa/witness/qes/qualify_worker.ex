defmodule Basa.Witness.QES.QualifyWorker do
  use Oban.Worker, queue: :default, max_attempts: 20, unique: [period: 300]

  alias Basa.Witness.{QES, QualifiedSignature, Transaction}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"id" => id}}) do
    record = Ash.get!(QualifiedSignature, id, authorize?: false)

    if record.status != :signed or record.qualification != :unchecked do
      :ok
    else
      tx = Ash.get!(Transaction, record.transaction_id, authorize?: false)

      case QES.qualification(record.cms, tx) do
        {%{qualification: :unchecked}, true} ->
          {:error, :dss_unreachable}

        {%{qualification: :unchecked}, false} ->
          {:cancel, :dss_not_configured}

        {attrs, _} ->
          record
          |> Ash.Changeset.for_update(:record_qualification, attrs)
          |> Ash.update!(authorize?: false)

          :ok
      end
    end
  end
end
