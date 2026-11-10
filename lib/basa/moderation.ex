defmodule Basa.Moderation do
  use Ash.Domain, otp_app: :basa

  require Ash.Query
  require Logger

  alias Basa.Moderation.PhotoCheck

  resources do
    resource PhotoCheck do
      define :list_to_review, action: :to_review
      define :list_my_hidden, action: :mine_hidden
      define :review_photo, action: :review, args: [:decision]
    end
  end

  def configured?, do: checker().available?()

  def enabled?, do: Basa.Services.on?(:moderation)

  @spec queue(String.t()) :: :ok
  def queue(key) when is_binary(key) do
    PhotoCheck
    |> Ash.Changeset.for_create(:queue, %{key: key})
    |> Ash.create(authorize?: false)
    |> case do
      {:ok, _} -> if enabled?(), do: enqueue([key])
      {:error, error} -> Logger.warning("photo check not queued for #{key}: #{inspect(error)}")
    end

    :ok
  rescue
    e ->
      Logger.warning("photo check not queued for #{key}: #{Exception.message(e)}")
      :ok
  end

  def enqueue(keys) do
    keys
    |> Enum.map(&Basa.Moderation.CheckWorker.new(%{key: &1}))
    |> Oban.insert_all()

    :ok
  end

  def catch_up do
    PhotoCheck
    |> Ash.Query.filter(status in [:pending, :failed])
    |> Ash.Query.select([:key])
    |> Ash.read!(authorize?: false)
    |> Enum.map(& &1.key)
    |> enqueue()
  end

  def recheck_all do
    Enum.each(photos_in_use(), &queue_quietly/1)

    keys =
      PhotoCheck
      |> Ash.Query.select([:key])
      |> Ash.read!(authorize?: false)
      |> Enum.map(& &1.key)

    keys
    |> Enum.chunk_every(500)
    |> Enum.each(fn chunk ->
      PhotoCheck
      |> Ash.Query.filter(key in ^chunk)
      |> Ash.bulk_update!(:requeue, %{}, authorize?: false, strategy: :stream)
    end)

    if enabled?(), do: enqueue(keys)
    length(keys)
  end

  def counts do
    count = fn query -> query |> Ash.count!(authorize?: false) end

    %{
      pending: count.(Ash.Query.filter(PhotoCheck, status == :pending)),
      review: count.(Ash.Query.for_read(PhotoCheck, :to_review))
    }
  end

  defp photos_in_use do
    read = fn resource -> Ash.read!(resource, authorize?: false) end

    items = Enum.flat_map(read.(Basa.Catalog.Item), &(&1.photos || []))

    rooms =
      Enum.flat_map(read.(Basa.Catalog.Room), fn r ->
        (r.photos || []) ++
          (r.entrance_photos || []) ++ List.wrap(r.street_view && r.street_view["key"])
      end)

    stock = Enum.map(read.(Basa.Images.StockImage), & &1.key)
    Enum.uniq(items ++ rooms ++ stock)
  end

  defp queue_quietly(key) do
    PhotoCheck
    |> Ash.Changeset.for_create(:queue, %{key: key})
    |> Ash.create(authorize?: false)
  end

  @spec hidden_keys([String.t()]) :: MapSet.t()
  def hidden_keys([]), do: MapSet.new()

  def hidden_keys(keys) do
    PhotoCheck
    |> Ash.Query.filter(key in ^keys)
    |> Ash.Query.filter(
      (verdict == :block and (is_nil(review) or review != :kept)) or review == :removed
    )
    |> Ash.Query.select([:key])
    |> Ash.read!(authorize?: false)
    |> MapSet.new(& &1.key)
  end

  def hidden_count(keys), do: keys |> hidden_keys() |> MapSet.size()

  def hidden?(key), do: MapSet.member?(hidden_keys([key]), key)

  def status do
    if configured?(), do: checker().status(), else: {:error, :not_installed}
  end

  def set_level(level) do
    if configured?(), do: checker().set_level(level), else: {:error, :not_installed}
  end

  def check(bytes), do: checker().check(bytes)

  @reasons %{
    "photo_nudity_clear" => "The photo looks like nudity, so it is hidden",
    "photo_nudity_possible" => "The photo may show nudity: an admin will check it",
    "photo_harm" => "The photo may show weapons, drugs or injuries: an admin will check it",
    "photo_documents" => "The photo may show a document or a bank card: an admin will check it"
  }

  def reason_text(code) do
    case Basa.I18n.t(code) do
      ^code -> Map.get(@reasons, code, code)
      text -> text
    end
  end

  def level_sizes, do: %{1 => 180_000_000, 2 => 265_000_000}

  def checker, do: Application.get_env(:basa, __MODULE__, [])[:checker] || Basa.Moderation.Checker
end
