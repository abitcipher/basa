defmodule Basa.Import.Agreement do
  use Ash.Resource,
    otp_app: :basa,
    domain: Basa.Import,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "import_agreements"
    repo Basa.Repo
  end

  actions do
    defaults [:read]

    create :publish do
      accept [:body]

      change fn changeset, context ->
        last =
          __MODULE__
          |> Ash.Query.sort(version: :desc)
          |> Ash.Query.limit(1)
          |> Ash.read_one!(authorize?: false)

        changeset
        |> Ash.Changeset.force_change_attribute(:version, if(last, do: last.version + 1, else: 1))
        |> Ash.Changeset.force_change_attribute(
          :published_by_email,
          context.actor && to_string(context.actor.email)
        )
      end
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if actor_present()
    end

    policy action(:publish) do
      authorize_if actor_attribute_equals(:role, :admin)
    end
  end

  validations do
    validate string_length(:body, min: 20, max: 50_000)
  end

  attributes do
    uuid_primary_key :id
    attribute :version, :integer, allow_nil?: false, public?: true
    attribute :body, :string, allow_nil?: false, public?: true, constraints: [trim?: true]
    attribute :published_by_email, :string, public?: true
    create_timestamp :inserted_at
  end

  identities do
    identity :unique_version, [:version]
  end

  def hash(%__MODULE__{body: body}),
    do: :crypto.hash(:sha256, body) |> Base.encode16(case: :lower)
end
