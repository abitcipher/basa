defmodule BasaWeb.PaymentController do
  use BasaWeb, :controller
  require Logger

  alias Basa.Payments.Settle

  def return(conn, %{"id" => id}) do
    with %{} = user <- conn.assigns[:current_user],
         {:ok, payment} <- Basa.Payments.get_payment(id, actor: user),
         {:ok, payment} <- Settle.refresh(payment) do
      conn
      |> put_flash(flash_kind(payment.status), message(payment))
      |> redirect(to: back_to(payment))
    else
      _ -> conn |> put_flash(:error, gettext("Payment not found.")) |> redirect(to: ~p"/")
    end
  end

  def webhook(conn, _params) do
    raw = BasaWeb.CacheBodyReader.raw_body(conn)
    signature = conn |> get_req_header("x-webhook-signature-512") |> List.first()

    with :ok <- Basa.Payments.Gateway.verify_webhook(raw, signature),
         {:ok, %{"content" => %{"object" => %{"payment_id" => provider_id}}}} <- Jason.decode(raw),
         {:ok, %{} = payment} <- Settle.by_provider_id(provider_id) do
      Settle.refresh(payment)
      send_resp(conn, 200, "ok")
    else
      {:error, :invalid_signature} ->
        Logger.warning("payment webhook with an invalid signature")
        send_resp(conn, 401, "invalid signature")

      _ ->
        send_resp(conn, 200, "ignored")
    end
  end

  defp flash_kind(:succeeded), do: :info
  defp flash_kind(:pending), do: :info
  defp flash_kind(_), do: :error

  defp message(%{status: :succeeded, purpose: :commission}),
    do: gettext("Thank you for supporting BASA!")

  defp message(%{status: :succeeded, purpose: :premium}),
    do: gettext("Paid. Your offer is now featured.")

  defp message(%{status: :pending}),
    do: gettext("Payment is being processed. We'll update it shortly.")

  defp message(_), do: gettext("The payment didn't go through. You can try again.")

  defp back_to(%{purpose: :commission}), do: ~p"/bookings?tab=incoming"
  defp back_to(_), do: ~p"/my"
end
