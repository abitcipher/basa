defmodule Basa.Messaging.Message do
  use Ash.Resource,
    otp_app: :basa,
    domain: Basa.Messaging,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "messages"
    repo Basa.Repo

    references do
      reference :conversation, on_delete: :delete
      reference :sender, on_delete: :delete
    end

    custom_indexes do
      index [:conversation_id, :inserted_at]
    end
  end

  actions do
    defaults [:read]

    read :in_conversation do
      argument :conversation_id, :uuid, allow_nil?: false
      filter expr(conversation_id == ^arg(:conversation_id))
      prepare build(sort: [inserted_at: :asc], limit: 200)
    end

    create :send do
      accept [:conversation_id, :body, :channel]
      change relate_actor(:sender)
      validate Basa.Messaging.Validations.Participant
      change Basa.Messaging.Changes.Deliver
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if expr(
                     conversation.lessor_id == ^actor(:id) or
                       conversation.lessee_id == ^actor(:id)
                   )
    end

    policy action(:send) do
      authorize_if actor_present()
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :body, :string do
      allow_nil? false
      public? true
      constraints min_length: 1, max_length: 4000, trim?: true
    end

    attribute :channel, :atom do
      constraints one_of: [:web, :telegram]
      default :web
      allow_nil? false
      public? true
    end

    create_timestamp :inserted_at, public?: true
  end

  relationships do
    belongs_to :conversation, Basa.Messaging.Conversation, allow_nil?: false, public?: true
    belongs_to :sender, Basa.Accounts.User, allow_nil?: false, public?: true
  end
end
