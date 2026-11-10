defmodule BasaWeb.QesController do
  use BasaWeb, :controller

  require Ash.Query

  alias Basa.Witness
  alias Basa.Witness.{QES, QualifiedSignature}

  def return(conn, %{"token" => token} = params) do
    user = conn.assigns[:current_user]

    with %{} <- user,
         {:ok, state} <- QES.state_from_token(token),
         %QualifiedSignature{user_id: user_id} = record when user_id == user.id <- pending(state),
         provider when not is_nil(provider) <- QES.provider(record.provider) do
      conn = finish(conn, record, provider.complete(record, params), user)

      if conn.halted,
        do: conn,
        else: redirect(conn, to: ~p"/transactions/#{record.transaction_id}")
    else
      _ ->
        conn
        |> put_flash(:error, gettext("This signing session is not valid any more."))
        |> redirect(to: ~p"/bookings")
    end
  end

  defp finish(conn, record, {:ok, cms}, user) do
    case Witness.complete_qualified_signature(record, cms, actor: user) do
      {:ok, _} ->
        put_flash(conn, :info, gettext("Your qualified signature was added to the contract."))

      {:error, error} ->
        Witness.fail_qualified_signature(record, Exception.message(error), actor: user)

        put_flash(
          conn,
          :error,
          gettext(
            "The signature was not accepted: it is not for this contract or not from a trusted certificate."
          )
        )
    end
  end

  defp finish(conn, record, {:continue, url, data}, user) do
    case Witness.advance_qualified_signature(record, data, actor: user) do
      {:ok, _} ->
        conn |> redirect(external: url) |> halt()

      {:error, _} ->
        put_flash(conn, :error, gettext("Signing was cancelled or failed. You can try again."))
    end
  end

  defp finish(conn, record, {:error, reason}, user) do
    Witness.fail_qualified_signature(record, inspect(reason), actor: user)
    put_flash(conn, :error, gettext("Signing was cancelled or failed. You can try again."))
  end

  defp pending(state) do
    QualifiedSignature
    |> Ash.Query.filter(state == ^state and status == :pending)
    |> Ash.read_one!(authorize?: false)
  end
end
