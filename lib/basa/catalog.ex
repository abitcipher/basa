defmodule Basa.Catalog do
  use Ash.Domain, otp_app: :basa, extensions: [AshTypescript.Rpc, AshJsonApi.Domain]

  typescript_rpc do
    resource Basa.Catalog.Lot do
      rpc_action(:lot_availability, :availability)
    end

    resource Basa.Catalog.Item do
      rpc_action(:my_items, :mine)
    end

    resource Basa.Catalog.Room do
      rpc_action(:my_rooms, :mine)
    end
  end

  json_api do
    routes do
      base_route "/categories", Basa.Catalog.Category do
        index :read
        get :read
      end

      base_route "/items", Basa.Catalog.Item do
        index :mine
        get :read
        post :api_create
        patch :api_update
        delete :destroy
      end

      base_route "/lots", Basa.Catalog.Lot do
        index :mine
        get :read
        post :create
        patch :update
        patch :submit, route: "/:id/submit"
        patch :archive, route: "/:id/archive"
      end
    end
  end

  resources do
    resource Basa.Catalog.Category do
      define :list_categories, action: :read
      define :get_category_by_slug, action: :read, get_by: [:slug]
    end

    resource Basa.Catalog.CatalogModel

    resource Basa.Catalog.Item do
      define :create_item, action: :create
      define :update_item, action: :update
      define :destroy_item, action: :destroy
      define :list_my_items, action: :mine
      define :get_item, action: :read, get_by: [:id]
    end

    resource Basa.Catalog.Attendant do
      define :create_attendant, action: :create
      define :list_my_attendants, action: :mine
    end

    resource Basa.Catalog.OfferBasket do
      define :create_basket, action: :create
      define :update_basket, action: :update
      define :list_my_baskets, action: :mine
      define :get_basket, action: :read, get_by: [:id]
    end

    resource Basa.Catalog.BasketItem
    resource Basa.Catalog.BasketAttendant

    resource Basa.Catalog.Room do
      define :create_room, action: :create
      define :update_room, action: :update
      define :list_my_rooms, action: :mine
      define :get_room, action: :read, get_by: [:id]
    end

    resource Basa.Catalog.Lot do
      define :create_lot, action: :create
      define :update_lot, action: :update
      define :submit_lot, action: :submit
      define :approve_lot, action: :approve
      define :reject_lot, action: :reject, args: [:review_note]
      define :archive_lot, action: :archive
      define :list_my_lots, action: :mine
      define :search_lots, action: :search
      define :get_lot, action: :read, get_by: [:id]
    end
  end
end
