defmodule Basa.Witness do
  use Ash.Domain, otp_app: :basa

  resources do
    resource Basa.Witness.Transaction do
      define :open_transaction, action: :open, args: [:booking_id]
      define :get_transaction, action: :read, get_by: [:id]
      define :update_terms, action: :update_terms
      define :declare_consumer, action: :declare_consumer, args: [:consumer]
      define :prepare_transaction, action: :prepare
      define :sign_transaction, action: :sign, args: [:signature]
      define :cancel_transaction, action: :cancel
    end

    resource Basa.Witness.AuthorityRequest do
      define :file_authority_request, action: :file, args: [:transaction_id]
      define :approve_authority_request, action: :approve
      define :reject_authority_request, action: :reject, args: [:decision_note]
      define :notify_authority_request, action: :notify
      define :record_kit_export, action: :record_export
      define :record_opening, action: :record_opening
    end

    resource Basa.Witness.MemAttestation do
      define :issue_mem_attestation, action: :issue, args: [:transaction_id]
      define :receive_mem_attestation, action: :receive, args: [:attestation, :via]
    end

    resource Basa.Witness.QualifiedSignature do
      define :start_qualified_signature, action: :start, args: [:transaction_id, :provider]
      define :complete_qualified_signature, action: :complete, args: [:cms]
      define :fail_qualified_signature, action: :fail, args: [:reason]
      define :advance_qualified_signature, action: :advance, args: [:provider_data]
    end

    resource Basa.Witness.Party do
      define :set_legal_name, action: :set_legal_name, args: [:legal_name]
      define :register_device, action: :register_device, args: [:public_key, :box_key]
    end

    resource Basa.Witness.Act do
      define :start_act, action: :start, args: [:transaction_id, :kind]
      define :edit_act, action: :edit, args: [:terms]
      define :fix_act, action: :fix
      define :sign_act, action: :sign, args: [:signature]
      define :countersign_act, action: :countersign, args: [:signature]
      define :reject_act, action: :reject
    end

    resource Basa.Witness.Evidence
    resource Basa.Witness.KeyShare
    resource Basa.Witness.AccessLog
  end

  def config, do: Application.get_env(:basa, __MODULE__, [])

  def storage_mode, do: Keyword.fetch!(config(), :storage_mode)

  def recovery_public_key, do: config()[:recovery_public_key]

  def recovery_private_key, do: config()[:recovery_private_key]

  def check_config!(env \\ Application.get_env(:basa, :env), config \\ config()) do
    if env == :prod do
      cond do
        config[:storage_mode] != :encrypted ->
          raise "witness: plain storage is for development and tests only; production must use :encrypted"

        config[:recovery_private_key] ->
          raise "witness: the recovery private key must never be on a server; remove it"

        not match?(<<_::binary-size(32)>>, config[:recovery_public_key]) ->
          raise "witness: set WITNESS_RECOVERY_PUBLIC_KEY (hex, 32 bytes) from the key ceremony"

        true ->
          :ok
      end
    else
      :ok
    end
  end
end
