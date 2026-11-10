defmodule Basa.Witness.AuthorityNotifyWorker do
  use Oban.Worker, queue: :notifications, max_attempts: 5
  use Gettext, backend: BasaWeb.Gettext

  require Ash.Query

  alias Basa.Witness.{AuthorityRequest, Party}

  def notify(%AuthorityRequest{} = request), do: Oban.insert!(new(%{request_id: request.id}))

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"request_id" => id}}) do
    request = Ash.get!(AuthorityRequest, id, authorize?: false)
    number = request.transaction_id |> String.slice(0, 8) |> String.upcase()

    for party <-
          Party
          |> Ash.Query.filter(transaction_id == ^request.transaction_id)
          |> Ash.Query.load(:user)
          |> Ash.read!(authorize?: false),
        party.user.telegram_id do
      Basa.Telegram.send_message(party.user.telegram_id, text(request, number, party.user.locale))
    end

    :ok
  end

  def text(request, number, locale) do
    Gettext.with_locale(BasaWeb.Gettext, to_string(locale || :en), fn ->
      gettext(
        "Contract No. %{number}: %{authority} was given access to its evidence (reference %{reference}). Details are on the contract page.",
        number: number,
        authority: request.authority,
        reference: request.reference
      )
    end)
  end
end
