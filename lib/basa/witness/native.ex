defmodule Basa.Witness.Native do
  use Rustler,
    otp_app: :basa,
    crate: "witness",
    mode: :release,
    skip_compilation?: System.get_env("WITNESS_NIF_PREBUILT") == "1"

  def sha256(_data), do: :erlang.nif_error(:nif_not_loaded)
  def merkle_root(_leaves), do: :erlang.nif_error(:nif_not_loaded)
  def merkle_proof(_leaves, _index), do: :erlang.nif_error(:nif_not_loaded)
  def merkle_verify(_root, _leaf, _index, _size, _proof), do: :erlang.nif_error(:nif_not_loaded)
  def manifest_encode(_manifest), do: :erlang.nif_error(:nif_not_loaded)
  def manifest_decode(_bytes), do: :erlang.nif_error(:nif_not_loaded)
  def data_key, do: :erlang.nif_error(:nif_not_loaded)
  def encrypt(_key, _plain, _aad), do: :erlang.nif_error(:nif_not_loaded)
  def decrypt(_key, _sealed, _aad), do: :erlang.nif_error(:nif_not_loaded)
  def split(_secret), do: :erlang.nif_error(:nif_not_loaded)
  def combine(_shares), do: :erlang.nif_error(:nif_not_loaded)
  def recovery_keypair, do: :erlang.nif_error(:nif_not_loaded)
  def recovery_seal(_public, _key, _transaction_id), do: :erlang.nif_error(:nif_not_loaded)
  def recovery_open(_private, _sealed, _transaction_id), do: :erlang.nif_error(:nif_not_loaded)
  def signing_keypair, do: :erlang.nif_error(:nif_not_loaded)
  def sign(_private, _message), do: :erlang.nif_error(:nif_not_loaded)
  def verify(_public, _message, _signature), do: :erlang.nif_error(:nif_not_loaded)
  def act_encode(_act), do: :erlang.nif_error(:nif_not_loaded)
  def device_seal(_public, _plain, _aad), do: :erlang.nif_error(:nif_not_loaded)
  def device_open(_private, _sealed, _aad), do: :erlang.nif_error(:nif_not_loaded)
  def act_decode(_bytes), do: :erlang.nif_error(:nif_not_loaded)

  def mem_request(_origin, _subject, _label, _role, _challenge, _submit_url),
    do: :erlang.nif_error(:nif_not_loaded)

  def mem_verify(_bytes), do: :erlang.nif_error(:nif_not_loaded)
  def qr_svg(_text), do: :erlang.nif_error(:nif_not_loaded)
  def qes_dev_ca(_seed), do: :erlang.nif_error(:nif_not_loaded)
  def qes_dev_sign(_seed, _user_id, _name, _digest), do: :erlang.nif_error(:nif_not_loaded)
  def qes_verify(_cms, _digest), do: :erlang.nif_error(:nif_not_loaded)
  def qes_issued_by(_cert, _issuer), do: :erlang.nif_error(:nif_not_loaded)
  def qes_prepare(_digest, _cert), do: :erlang.nif_error(:nif_not_loaded)

  def qes_assemble(_certs, _signed_attrs, _signature, _alg),
    do: :erlang.nif_error(:nif_not_loaded)

  def qes_dev_remote(_seed, _user_id, _name, _hash), do: :erlang.nif_error(:nif_not_loaded)
end
