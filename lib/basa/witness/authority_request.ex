defmodule Basa.Witness.AuthorityRequest do
  use Ash.Resource,
    otp_app: :basa,
    domain: Basa.Witness,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias Basa.Witness.Changes.AuthorityStep

  postgres do
    table "witness_authority_requests"
    repo Basa.Repo

    references do
      reference :transaction, on_delete: :restrict
    end
  end

  actions do
    defaults [:read]

    create :file do
      accept [
        :authority,
        :basis,
        :reference,
        :received_on,
        :notes,
        :notify_parties,
        :no_notice_reason
      ]

      argument :transaction_id, :uuid, allow_nil?: false
      change set_attribute(:transaction_id, arg(:transaction_id))
      change relate_actor(:filed_by)

      validate fn changeset, _ ->
        id = Ash.Changeset.get_argument(changeset, :transaction_id)

        case id && Ash.get(Basa.Witness.Transaction, id, authorize?: false) do
          {:ok, %{basa_hash: hash}} when is_binary(hash) ->
            :ok

          _ ->
            {:error,
             field: :transaction_id, message: "only a sealed contract has evidence to give"}
        end
      end

      validate fn changeset, _ ->
        notify = Ash.Changeset.get_attribute(changeset, :notify_parties)
        reason = Ash.Changeset.get_attribute(changeset, :no_notice_reason)

        if notify == false and reason in [nil, ""],
          do: {:error, field: :no_notice_reason, message: "say why the parties may not be told"},
          else: :ok
      end

      change {AuthorityStep, step: :filed}
    end

    update :approve do
      require_atomic? false
      validate attribute_equals(:status, :pending), message: "already decided"
      validate {Basa.Witness.Validations.SecondAdmin, []}
      change set_attribute(:status, :approved)
      change relate_actor(:decided_by)
      change set_attribute(:decided_at, &DateTime.utc_now/0)
      change {AuthorityStep, step: :approved}
    end

    update :reject do
      require_atomic? false
      argument :decision_note, :string, allow_nil?: false
      validate attribute_equals(:status, :pending), message: "already decided"
      validate {Basa.Witness.Validations.SecondAdmin, []}
      change set_attribute(:status, :rejected)
      change set_attribute(:decision_note, arg(:decision_note))
      change relate_actor(:decided_by)
      change set_attribute(:decided_at, &DateTime.utc_now/0)
      change {AuthorityStep, step: :rejected}
    end

    update :notify do
      require_atomic? false
      validate attribute_in(:status, [:approved, :opened]), message: "not approved"
      validate attribute_equals(:parties_notified_at, nil), message: "already told"
      change {AuthorityStep, step: :notified}
    end

    update :record_export do
      require_atomic? false
      validate attribute_in(:status, [:approved, :opened]), message: "not approved"
      change set_attribute(:kit_exported_at, &DateTime.utc_now/0)
      change {AuthorityStep, step: :exported}
    end

    update :record_opening do
      require_atomic? false
      accept [:key_holders, :handed_over_to, :report_sha256]
      validate attribute_equals(:status, :approved), message: "not approved, or already opened"
      validate present([:key_holders, :handed_over_to, :report_sha256])

      validate fn changeset, _ ->
        case Ash.Changeset.get_attribute(changeset, :report_sha256) do
          <<_::binary-size(32)>> -> :ok
          _ -> {:error, field: :report_sha256, message: "the SHA-256 of the opening report"}
        end
      end

      change set_attribute(:status, :opened)
      change set_attribute(:opened_at, &DateTime.utc_now/0)
      change {AuthorityStep, step: :opened}
    end
  end

  policies do
    bypass actor_attribute_equals(:role, :admin) do
      authorize_if always()
    end

    policy action_type(:read) do
      authorize_if expr(
                     not is_nil(parties_notified_at) and
                       exists(transaction.parties, user_id == ^actor(:id))
                   )
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :authority, :string, allow_nil?: false, public?: true

    attribute :basis, :atom do
      constraints one_of: [:court_order, :lawful_request, :parties_cannot_act]
      allow_nil? false
      public? true
    end

    attribute :reference, :string, allow_nil?: false, public?: true
    attribute :received_on, :date, public?: true
    attribute :notes, :string, public?: true

    attribute :notify_parties, :boolean, default: true, allow_nil?: false, public?: true
    attribute :no_notice_reason, :string, public?: true

    attribute :status, :atom do
      constraints one_of: [:pending, :approved, :rejected, :opened]
      default :pending
      allow_nil? false
      public? true
    end

    attribute :decided_at, :utc_datetime_usec, public?: true
    attribute :decision_note, :string, public?: true
    attribute :parties_notified_at, :utc_datetime_usec, public?: true
    attribute :kit_exported_at, :utc_datetime_usec, public?: true
    attribute :opened_at, :utc_datetime_usec, public?: true

    attribute :key_holders, :string, public?: true
    attribute :handed_over_to, :string, public?: true
    attribute :report_sha256, :binary, public?: true

    timestamps()
  end

  relationships do
    belongs_to :transaction, Basa.Witness.Transaction, allow_nil?: false, public?: true
    belongs_to :filed_by, Basa.Accounts.User, public?: true
    belongs_to :decided_by, Basa.Accounts.User, public?: true
  end
end
