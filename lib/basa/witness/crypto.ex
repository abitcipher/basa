defmodule Basa.Witness.Crypto do
  alias Basa.Witness.Native

  @text_prefix "basa0:"
  @seal_context "BASA/v1/seal"
  @share_owners [:offeror, :acceptor, :basa]

  def hash(data) when is_binary(data), do: :crypto.hash(:sha256, data)

  def hash_file(path) do
    path
    |> File.stream!(1_048_576)
    |> Enum.reduce(:crypto.hash_init(:sha256), &:crypto.hash_update(&2, &1))
    |> :crypto.hash_final()
  end

  def merkle_root(hashes), do: Native.merkle_root(hashes)

  def merkle_proof(hashes, index), do: Native.merkle_proof(hashes, index)

  def merkle_verify(root, hash, index, size, proof),
    do: Native.merkle_verify(root, hash, index, size, proof)

  def encode_manifest(manifest) do
    manifest
    |> Map.put_new(:geo, nil)
    |> Map.put(:merkle_root, nil)
    |> Native.manifest_encode()
  end

  def decode_manifest(bytes), do: Native.manifest_decode(bytes)

  def basa_hash(manifest_bytes), do: hash(manifest_bytes)

  def to_text(<<_::binary-size(32)>> = basa_hash),
    do: @text_prefix <> Base.encode32(basa_hash, case: :lower, padding: false)

  def from_text(@text_prefix <> encoded) do
    case Base.decode32(encoded, case: :lower, padding: false) do
      {:ok, <<_::binary-size(32)>> = h} -> {:ok, h}
      _ -> :error
    end
  end

  def from_text(_), do: :error

  def seal_message(<<_::binary-size(32)>> = basa_hash), do: @seal_context <> basa_hash

  def verify_seal(public_key, basa_hash, signature)
      when is_binary(public_key) and is_binary(signature),
      do: Native.verify(public_key, seal_message(basa_hash), signature)

  def signing_keypair, do: Native.signing_keypair()

  def sign_seal(private_key, basa_hash), do: Native.sign(private_key, seal_message(basa_hash))

  def seal_for_device(device_public_key, share, aad),
    do: Native.device_seal(device_public_key, share, aad)

  def open_for_device(device_private_key, sealed, aad),
    do: Native.device_open(device_private_key, sealed, aad)

  @act_context "BASA/v1/act"

  def encode_act(act) do
    act
    |> Map.update!(:terms, fn terms ->
      Enum.map(terms, fn {k, v} -> {to_string(k), to_string(v)} end)
    end)
    |> Native.act_encode()
  end

  def decode_act(bytes) do
    with {:ok, act} <- Native.act_decode(bytes), do: {:ok, Map.update!(act, :terms, &Map.new/1)}
  end

  def act_message(<<_::binary-size(32)>> = act_hash), do: @act_context <> act_hash

  def verify_act(public_key, act_hash, signature)
      when is_binary(public_key) and is_binary(signature),
      do: Native.verify(public_key, act_message(act_hash), signature)

  def verify_act(_, _, _), do: false

  def sign_act(private_key, act_hash), do: Native.sign(private_key, act_message(act_hash))

  def new_key(transaction_id, recovery_public_key) do
    with {:ok, key} <- Native.data_key(),
         {:ok, shares} <- Native.split(key),
         {:ok, recovery} <- Native.recovery_seal(recovery_public_key, key, transaction_id) do
      {:ok, %{key: key, shares: Map.new(Enum.zip(@share_owners, shares)), recovery: recovery}}
    end
  end

  def encrypt(key, plain), do: Native.encrypt(key, plain, hash(plain))

  def decrypt(key, sealed, file_hash), do: Native.decrypt(key, sealed, file_hash)

  def combine(shares), do: Native.combine(shares)

  def recover(recovery_private_key, sealed, transaction_id),
    do: Native.recovery_open(recovery_private_key, sealed, transaction_id)

  def recovery_keypair, do: Native.recovery_keypair()

  def key_check(%{key: key, shares: shares, recovery: recovery}, plain, opts \\ []) do
    file_hash = hash(plain)
    {:ok, sealed} = encrypt(key, plain)

    pairs = [
      {:offeror_acceptor, [shares.offeror, shares.acceptor]},
      {:offeror_basa, [shares.offeror, shares.basa]},
      {:acceptor_basa, [shares.acceptor, shares.basa]}
    ]

    opens =
      Enum.map(pairs, fn {name, pair} -> {name, opens?(combine(pair), sealed, file_hash)} end)

    recovery_check =
      case Keyword.fetch(opts, :recovery_private_key) do
        {:ok, private} ->
          [
            {:recovery,
             opens?(
               recover(private, recovery, Keyword.fetch!(opts, :transaction_id)),
               sealed,
               file_hash
             )}
          ]

        :error ->
          []
      end

    single = for {owner, share} <- shares, do: {:"#{owner}_alone", combine([share]) |> refused?()}

    case for({name, false} <- opens ++ recovery_check ++ single, do: name) do
      [] -> :ok
      failures -> {:error, failures}
    end
  end

  defp opens?({:ok, key}, sealed, file_hash) do
    case decrypt(key, sealed, file_hash) do
      {:ok, plain} -> hash(plain) == file_hash
      _ -> false
    end
  end

  defp opens?(_, _, _), do: false

  defp refused?({:error, _}), do: true
  defp refused?(_), do: false
end
