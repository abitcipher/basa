defmodule Basa.Services do
  @services [
    :telegram,
    :email,
    :mem,
    :qes,
    :timestamp,
    :osm,
    :images,
    :import,
    :street_view,
    :moderation,
    :ai,
    :payments
  ]

  def all, do: @services

  def on?(service) when service in @services,
    do: configured?(service) and not switched_off?(service)

  def switched_off?(service) when service in @services,
    do: service in Basa.System.settings().services_off

  def configured?(:telegram), do: Basa.Telegram.configured?()
  def configured?(:email), do: Basa.Mailer.configured?()
  def configured?(:mem), do: true
  def configured?(:qes), do: Basa.Witness.QES.configured_providers() != []
  def configured?(:timestamp), do: Basa.Witness.Timestamp.configured?()
  def configured?(:osm), do: Basa.Geo.Photon.configured?()
  def configured?(:images), do: Basa.Images.configured?()
  def configured?(:import), do: Basa.Import.configured?()
  def configured?(:street_view), do: Basa.StreetView.configured?()
  def configured?(:moderation), do: Basa.Moderation.configured?()
  def configured?(:ai), do: Basa.AI.configured?()
  def configured?(:payments), do: Basa.Payments.configured?()

  def caught_up(:timestamp) do
    require Ash.Query

    Basa.Witness.Transaction
    |> Ash.Query.filter(not is_nil(basa_hash) and is_nil(timestamp_token))
    |> Ash.Query.filter(status not in [:draft, :signing, :cancelled])
    |> Ash.read!(authorize?: false)
    |> Enum.map(&Basa.Witness.TimestampWorker.new(%{transaction_id: &1.id}))
    |> Oban.insert_all()

    :ok
  end

  def caught_up(:qes) do
    require Ash.Query

    Basa.Witness.QualifiedSignature
    |> Ash.Query.filter(status == :signed and qualification == :unchecked)
    |> Ash.read!(authorize?: false)
    |> Enum.map(&Basa.Witness.QES.QualifyWorker.new(%{"id" => &1.id}))
    |> Oban.insert_all()

    :ok
  end

  def caught_up(:moderation), do: Basa.Moderation.catch_up()

  def caught_up(_service), do: :ok
end
