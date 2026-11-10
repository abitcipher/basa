defmodule Basa.Messaging.Conversation do
  use Ash.Resource,
    otp_app: :basa,
    domain: Basa.Messaging,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "conversations"
    repo Basa.Repo

    references do
      reference :lot, on_delete: :delete
      reference :lessor, on_delete: :delete
      reference :lessee, on_delete: :delete
    end
  end

  actions do
    defaults [:read]

    read :mine do
      filter expr(lessor_id == ^actor(:id) or lessee_id == ^actor(:id))
      prepare build(sort: [last_message_at: :desc_nils_last], load: [:lot, :lessor, :lessee])
    end

    create :start do
      accept [:lot_id]
      upsert? true
      upsert_identity :unique_lot_lessee
      upsert_fields [:updated_at]
      change relate_actor(:lessee)
      change Basa.Messaging.Changes.SetLessor
    end

    update :touch do
      require_atomic? false
      accept []
      argument :sender_id, :uuid, allow_nil?: false
      change set_attribute(:last_message_at, &DateTime.utc_now/0)
      change Basa.Messaging.Changes.MarkUnreadForOther
    end

    update :mark_read do
      require_atomic? false
      accept []
      change Basa.Messaging.Changes.MarkRead
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if expr(lessor_id == ^actor(:id) or lessee_id == ^actor(:id))
    end

    policy action(:start) do
      authorize_if actor_present()
    end

    policy action(:mark_read) do
      authorize_if expr(lessor_id == ^actor(:id) or lessee_id == ^actor(:id))
    end

    policy action(:touch) do
      forbid_if always()
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :last_message_at, :utc_datetime_usec, public?: true
    attribute :lessor_unread, :boolean, default: false, allow_nil?: false, public?: true
    attribute :lessee_unread, :boolean, default: false, allow_nil?: false, public?: true
    timestamps()
  end

  relationships do
    belongs_to :lot, Basa.Catalog.Lot, allow_nil?: false, public?: true
    belongs_to :lessor, Basa.Accounts.User, allow_nil?: false, public?: true
    belongs_to :lessee, Basa.Accounts.User, allow_nil?: false, public?: true
    has_many :messages, Basa.Messaging.Message
  end

  identities do
    identity :unique_lot_lessee, [:lot_id, :lessee_id]
  end

  def other_party(%{lessor_id: me, lessee_id: other}, me), do: other
  def other_party(%{lessor_id: other}, _me), do: other

  def unread_for?(%{lessor_id: id, lessor_unread: u}, id), do: u
  def unread_for?(%{lessee_id: id, lessee_unread: u}, id), do: u
  def unread_for?(_, _), do: false
end
