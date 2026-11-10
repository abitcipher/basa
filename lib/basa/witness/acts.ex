defmodule Basa.Witness.Acts do
  require Ash.Query

  alias Basa.Witness.{Act, Crypto, Evidence, Party, Transaction}

  def allowed?(%Transaction{} = tx, kind, role, now \\ DateTime.utc_now()) do
    case {tx.contract_type, kind, role, tx.status} do
      {:lease, :return, :acceptor, :sealed} -> :ok
      {:lease, :acceptance, :offeror, :returned} -> :ok
      {:lease, :claim, :offeror, :returned} -> within_window(tx, now)
      {:lease, :auto_acceptance, :basa, :returned} -> window_over(tx, now)
      {:sale, :delivery, :acceptor, :sealed} -> :ok
      {:sale, :acceptance, :acceptor, :delivered} -> :ok
      {:sale, :claim, :acceptor, :delivered} -> within_window(tx, now)
      {:sale, :auto_acceptance, :basa, :delivered} -> window_over(tx, now)
      {_, :settlement, role, :claimed} when role in [:offeror, :acceptor] -> :ok
      {_, :dispute, role, :claimed} when role in [:offeror, :acceptor] -> :ok
      _ -> {:error, "this act is not possible now"}
    end
  end

  defp within_window(%{claims_until: until}, now) do
    if until && DateTime.compare(now, until) != :gt,
      do: :ok,
      else: {:error, "the claims window is over"}
  end

  defp window_over(%{claims_until: until}, now) do
    if until && DateTime.compare(now, until) != :lt,
      do: :ok,
      else: {:error, "the claims window is still open"}
  end

  def party(%Transaction{id: id}, user_id) do
    Party
    |> Ash.Query.filter(transaction_id == ^id and user_id == ^user_id)
    |> Ash.read_one!(authorize?: false)
  end

  def parties(%Transaction{id: id}),
    do: Party |> Ash.Query.filter(transaction_id == ^id) |> Ash.read!(authorize?: false)

  def files(act_id) do
    Evidence
    |> Ash.Query.filter(act_id == ^act_id)
    |> Ash.Query.sort(position: :asc)
    |> Ash.read!(authorize?: false)
  end

  def chain(%Transaction{id: id}) do
    Act
    |> Ash.Query.filter(transaction_id == ^id and not is_nil(sequence))
    |> Ash.Query.sort(sequence: :asc)
    |> Ash.read!(authorize?: false)
  end

  def tail(%Transaction{} = tx) do
    case List.last(chain(tx)) do
      nil -> {tx.basa_hash, 1}
      last -> {last.hash, last.sequence + 1}
    end
  end

  def check_content(kind, terms, files, %Transaction{} = tx) do
    cond do
      kind in [:return, :delivery] and not Enum.any?(files, &(&1.kind == :photo)) ->
        {:error, "add photos of the condition you return it in"}

      kind in [:claim, :settlement, :dispute] and blank?(terms["note"]) ->
        {:error, "describe it in a few words"}

      kind == :settlement ->
        check_kept(terms["deposit_kept"], tx.deposit_amount)

      kind == :claim and not blank?(terms["amount"]) ->
        check_amount(terms["amount"])

      true ->
        :ok
    end
  end

  defp check_kept(_kept, nil), do: :ok

  defp check_kept(kept, deposit) do
    case Decimal.parse(kept || "") do
      {d, ""} ->
        if Decimal.compare(d, 0) != :lt and Decimal.compare(d, deposit) != :gt,
          do: :ok,
          else: {:error, "the kept part must be between 0 and the deposit"}

      _ ->
        {:error, "say how much of the deposit the lessor keeps"}
    end
  end

  defp check_amount(amount) do
    case Decimal.parse(amount) do
      {d, ""} ->
        if Decimal.compare(d, 0) == :gt, do: :ok, else: {:error, "the amount must be positive"}

      _ ->
        {:error, "the amount must be a number"}
    end
  end

  defp blank?(s), do: s in [nil, ""] or String.trim(s) == ""

  def encode(%Transaction{} = tx, kind, author, terms, files, previous, now) do
    act = %{
      basa_hash: tx.basa_hash,
      previous: previous,
      kind: to_string(kind),
      author: to_string(author),
      created_at: now |> DateTime.truncate(:second) |> DateTime.to_iso8601(),
      files:
        for(
          f <- files,
          do: %{sha256: f.sha256, kind: to_string(f.kind), size: f.size, media_type: f.media_type}
        ),
      terms: terms
    }

    with {:ok, bytes} <- Crypto.encode_act(act), do: {:ok, bytes, Crypto.basa_hash(bytes)}
  end

  def apply_effect(%Act{} = act) do
    tx = Ash.get!(Transaction, act.transaction_id, authorize?: false)
    now = DateTime.utc_now()

    changes =
      case act.kind do
        :return ->
          %{status: :returned, returned_at: now, claims_until: claims_window(tx, now)}

        :delivery ->
          Basa.Catalog.Sold.mark(tx.booking_id)
          %{status: :delivered, returned_at: now, claims_until: claims_window(tx, now)}

        kind when kind in [:acceptance, :auto_acceptance] ->
          %{status: :closed, closed_at: now, deposit_status: release(tx.deposit_status)}

        :claim ->
          %{status: :claimed}

        :settlement ->
          kept = Decimal.new(act.terms["deposit_kept"] || "0")

          %{
            status: :settled,
            closed_at: now,
            deposit_kept: kept,
            deposit_status: settled(tx, kept)
          }

        :dispute ->
          %{status: :disputed}
      end

    Ash.update!(tx, changes, action: :apply_act, authorize?: false)
  end

  defp claims_window(tx, now) do
    until = DateTime.add(now, tx.claims_window_days * 86_400)

    Oban.insert!(
      Basa.Witness.Acts.AutoAcceptWorker.new(%{transaction_id: tx.id}, scheduled_at: until)
    )

    until
  end

  defp release(:held), do: :released
  defp release(other), do: other

  defp settled(%{deposit_status: :held, deposit_amount: amount}, kept) do
    cond do
      Decimal.equal?(kept, 0) -> :released
      Decimal.equal?(kept, amount) -> :kept
      true -> :partly_kept
    end
  end

  defp settled(tx, _kept), do: tx.deposit_status
end
