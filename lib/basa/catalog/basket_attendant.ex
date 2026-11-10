defmodule Basa.Catalog.BasketAttendant do
  use Ash.Resource,
    otp_app: :basa,
    domain: Basa.Catalog,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "basket_attendants"
    repo Basa.Repo

    references do
      reference :basket, on_delete: :delete
      reference :attendant, on_delete: :delete
    end
  end

  actions do
    defaults [:read, :destroy, create: :*]
  end

  policies do
    policy always() do
      authorize_if expr(basket.owner_id == ^actor(:id))
      authorize_if expr(exists(basket.lots, state == :published))
    end
  end

  relationships do
    belongs_to :basket, Basa.Catalog.OfferBasket, primary_key?: true, allow_nil?: false
    belongs_to :attendant, Basa.Catalog.Attendant, primary_key?: true, allow_nil?: false
  end
end
