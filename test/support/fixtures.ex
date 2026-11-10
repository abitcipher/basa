defmodule Basa.Fixtures do
  alias Basa.Catalog

  def user(attrs \\ %{}) do
    n = System.unique_integer([:positive])

    Ash.Seed.seed!(
      Basa.Accounts.User,
      Map.merge(
        %{
          email: "user#{n}@example.com",
          hashed_password: Bcrypt.hash_pwd_salt("password1234"),
          confirmed_at: DateTime.utc_now(),
          display_name: "User #{n}",
          locale: :en
        },
        attrs
      )
    )
  end

  def category(attrs \\ %{}) do
    n = System.unique_integer([:positive])

    Ash.Seed.seed!(
      Catalog.Category,
      Map.merge(%{slug: "cat-#{n}", name: %{"en" => "Category #{n}"}, kind: :equipment}, attrs)
    )
  end

  def item(owner, attrs \\ %{}) do
    Catalog.create_item!(
      Map.merge(
        %{title: "Shure SM7B", brand: "Shure", model: "SM7B", estimated_value: 18_000},
        attrs
      ),
      actor: owner
    )
  end

  @cities %{
    "Odesa" => %{
      id: "gn:698740",
      country_code: "UA",
      admin1: "Odesa",
      lat: 46.4775,
      lng: 30.7326,
      timezone: "Europe/Kyiv",
      population: 1_010_537,
      names: %{"en" => "Odesa", "uk" => "Одеса", "de" => "Odessa", "fr" => "Odessa"}
    },
    "Berlin" => %{
      id: "gn:2950159",
      country_code: "DE",
      admin1: "State of Berlin",
      lat: 52.5244,
      lng: 13.4105,
      timezone: "Europe/Berlin",
      population: 3_426_354,
      names: %{"en" => "Berlin", "uk" => "Берлін", "de" => "Berlin", "fr" => "Berlin"}
    },
    "Madrid" => %{
      id: "gn:3117735",
      country_code: "ES",
      admin1: "Madrid",
      lat: 40.4165,
      lng: -3.7026,
      timezone: "Europe/Madrid",
      population: 3_255_944,
      names: %{"en" => "Madrid", "uk" => "Мадрид", "de" => "Madrid", "fr" => "Madrid"}
    }
  }

  def geo_city(name, attrs \\ %{}) do
    base =
      Map.get(@cities, name, %{
        id: "gn:#{System.unique_integer([:positive])}",
        country_code: "UA",
        lat: 50.0,
        lng: 30.0,
        timezone: "Europe/Kyiv",
        population: 100_000,
        names: %{"en" => name}
      })

    Basa.Geo.City
    |> Ash.Changeset.for_create(
      :import,
      Map.merge(Map.merge(base, %{source: :geonames, name: name, ascii_name: name}), attrs),
      authorize?: false
    )
    |> Ash.create!()
  end

  def room(owner, attrs \\ %{}) do
    Catalog.create_room!(
      Map.merge(%{title: "Studio A", city: "Odesa", lat: 46.4825, lng: 30.7233}, attrs),
      actor: owner
    )
  end

  def basket(owner, items, attrs \\ %{}) do
    Catalog.create_basket!(
      Map.merge(%{title: "Vocal recording kit", item_ids: Enum.map(items, & &1.id)}, attrs),
      actor: owner
    )
  end

  def lot(owner, basket, room, attrs \\ %{}) do
    Catalog.create_lot!(
      Map.merge(
        %{
          title: "Vocal studio, hourly",
          basket_id: basket.id,
          room_id: room.id,
          price_amount: 500,
          currency: :UAH,
          price_unit: :hour,
          timezone: "Etc/UTC"
        },
        attrs
      ),
      actor: owner
    )
  end

  def published_lot(owner, basket, room, attrs \\ %{}) do
    owner |> lot(basket, room, attrs) |> Catalog.submit_lot!(actor: owner)
  end

  def hours_from_now(hours) do
    DateTime.utc_now()
    |> DateTime.add(hours * 3600, :second)
    |> Map.merge(%{minute: 0, second: 0, microsecond: {0, 6}})
  end
end
