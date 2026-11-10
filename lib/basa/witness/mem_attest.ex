defmodule Basa.Witness.MemAttest do
  require Ash.Query

  alias Basa.Witness.{Crypto, MemAttestation, Native, Transaction}

  @window_minutes 15
  @request_prefix "memattreq1:"
  @attestation_prefix "memattsig1:"

  def origin, do: BasaWeb.Endpoint.url()

  def submit_url(%MemAttestation{challenge: c}),
    do: origin() <> "/mem/attest/" <> Base.url_encode64(c, padding: false)

  def challenge_from_token(token) do
    case Base.url_decode64(token, padding: false) do
      {:ok, <<_::binary-size(16)>> = c} -> {:ok, c}
      _ -> :error
    end
  end

  def label(%Transaction{basa_hash: hash}), do: String.slice(Crypto.to_text(hash), 0, 26)

  def request_text(%MemAttestation{} = a, %Transaction{} = tx) do
    {:ok, cbor} =
      Native.mem_request(
        origin(),
        tx.basa_hash,
        label(tx),
        to_string(a.role),
        a.challenge,
        submit_url(a)
      )

    @request_prefix <> Base.url_encode64(cbor, padding: false)
  end

  def from_text(text) when is_binary(text) do
    with [_, body | _] <- String.split(String.trim(text), @attestation_prefix, parts: 2),
         body = body |> String.split() |> List.first(""),
         {:ok, bytes} <- Base.url_decode64(body, padding: false) do
      {:ok, bytes}
    else
      _ -> {:error, :not_an_attestation}
    end
  end

  def check(%MemAttestation{} = record, %Transaction{} = tx, bytes, now \\ DateTime.utc_now()) do
    other = if record.role == :offeror, do: "acceptor", else: "offeror"

    with :ok <- if(record.status == :pending, do: :ok, else: {:error, :already_received}),
         :ok <- in_window(record, now),
         {:ok, a} <- verify(bytes),
         :ok <- same(a.origin, origin(), :wrong_origin),
         :ok <- same(a.subject, tx.basa_hash, :wrong_contract),
         :ok <- same(a.challenge, record.challenge, :wrong_challenge),
         signer = if(a.lo.public_key == a.signer, do: a.lo, else: a.hi),
         peer = if(a.lo.public_key == a.signer, do: a.hi, else: a.lo),
         :ok <- same(signer.role, to_string(record.role), :wrong_role),
         :ok <- same(peer.role, other, :wrong_role) do
      {:ok, a}
    end
  end

  def verify(bytes) when is_binary(bytes) do
    case Native.mem_verify(bytes) do
      {:ok, a} -> {:ok, a}
      {:error, reason} -> {:error, {:invalid, reason}}
    end
  end

  def verify(_), do: {:error, {:invalid, "not bytes"}}

  def pair_check(offeror_bytes, acceptor_bytes, basa_hash) do
    with {:ok, o} <- verify(offeror_bytes),
         {:ok, a} <- verify(acceptor_bytes),
         true <- (o.statement == a.statement and o.signer != a.signer) || {:error, :mismatch},
         true <- (o.subject == basa_hash and o.origin == origin()) || {:error, :mismatch},
         true <- (role_of(o) == "offeror" and role_of(a) == "acceptor") || {:error, :mismatch} do
      :ok
    else
      {:error, {:invalid, _}} -> {:error, :bad_signature}
      {:error, reason} -> {:error, reason}
    end
  end

  defp role_of(%{signer: s, lo: lo, hi: hi}),
    do: if(lo.public_key == s, do: lo.role, else: hi.role)

  def confirmed_pair(%Transaction{id: id}) do
    received =
      MemAttestation
      |> Ash.Query.filter(transaction_id == ^id and status == :received)
      |> Ash.Query.sort(received_at: :desc)
      |> Ash.read!(authorize?: false)

    {offerors, acceptors} = Enum.split_with(received, &(&1.role == :offeror))

    Enum.find_value(offerors, fn o ->
      a = Enum.find(acceptors, &(&1.statement == o.statement))
      a && {o, a}
    end)
  end

  defp in_window(record, now) do
    if DateTime.diff(now, record.inserted_at, :minute) < @window_minutes,
      do: :ok,
      else: {:error, :expired}
  end

  defp same(a, a, _reason), do: :ok
  defp same(_, _, reason), do: {:error, reason}

  defmodule Issue do
    use Ash.Resource.Change

    require Ash.Query

    @impl true
    def change(changeset, _opts, %{actor: actor}) do
      id = Ash.Changeset.get_argument(changeset, :transaction_id)

      party =
        actor && id &&
          Basa.Witness.Party
          |> Ash.Query.filter(transaction_id == ^id and user_id == ^actor.id)
          |> Ash.read_one!(authorize?: false)

      tx = id && Ash.get!(Basa.Witness.Transaction, id, authorize?: false, error?: false)

      cond do
        is_nil(party) ->
          Ash.Changeset.add_error(changeset, field: :transaction_id, message: "not a party")

        is_nil(tx) or is_nil(tx.basa_hash) ->
          Ash.Changeset.add_error(changeset,
            field: :transaction_id,
            message: "only a sealed contract can be confirmed in person"
          )

        not Basa.Services.on?(:mem) ->
          Ash.Changeset.add_error(changeset,
            field: :transaction_id,
            message: "confirming in person in MEM is switched off"
          )

        true ->
          changeset
          |> Ash.Changeset.force_change_attribute(:role, party.role)
          |> Ash.Changeset.force_change_attribute(:user_id, actor.id)
          |> Ash.Changeset.force_change_attribute(:challenge, :crypto.strong_rand_bytes(16))
      end
    end
  end

  defmodule Receive do
    use Ash.Resource.Change

    alias Basa.Witness.MemAttest

    @impl true
    def change(changeset, _opts, _context) do
      record = changeset.data
      bytes = Ash.Changeset.get_argument(changeset, :attestation)
      tx = Ash.get!(Basa.Witness.Transaction, record.transaction_id, authorize?: false)

      case MemAttest.check(record, tx, bytes) do
        {:ok, a} ->
          changeset
          |> Ash.Changeset.force_change_attributes(%{
            status: :received,
            attestation: bytes,
            statement: a.statement,
            attest_key: a.signer,
            via: Ash.Changeset.get_argument(changeset, :via),
            received_at: DateTime.utc_now()
          })
          |> Ash.Changeset.after_action(fn _cs, result ->
            confirm(tx)
            Phoenix.PubSub.broadcast(Basa.PubSub, "witness:#{tx.id}", :witness_changed)
            {:ok, result}
          end)

        {:error, reason} ->
          Ash.Changeset.add_error(changeset,
            field: :attestation,
            message: "not accepted: %{reason}",
            vars: [reason: inspect(reason)]
          )
      end
    end

    defp confirm(%{mem_confirmed_at: nil} = tx) do
      if MemAttest.confirmed_pair(tx) do
        tx
        |> Ash.Changeset.for_update(:confirm_in_person, %{})
        |> Ash.update!(authorize?: false)
      end
    end

    defp confirm(_tx), do: :ok
  end
end
