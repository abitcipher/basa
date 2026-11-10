defmodule BasaWeb.EvidenceController do
  use BasaWeb, :controller

  require Ash.Query

  alias Basa.Witness.{AccessLog, Evidence, Party, Store}

  def show(conn, %{"id" => id, "position" => position} = params) do
    user = conn.assigns[:current_user]

    with %{} <- user,
         {pos, ""} <- Integer.parse(position),
         {:ok, tx} <- Basa.Witness.get_transaction(id, authorize?: false),
         true <- party?(tx, user),
         %Evidence{} = e <-
           Evidence
           |> Ash.Query.filter(transaction_id == ^tx.id and position == ^pos)
           |> act_files(params["act_id"])
           |> Ash.read_one!(authorize?: false),
         {:ok, body} <- Store.read(e, tx, share: ticket(params, user, e.act_id || tx.id)) do
      Ash.create!(
        AccessLog,
        %{
          transaction_id: tx.id,
          action: :open,
          actor_id: user.id,
          reason: "party download",
          result: "ok"
        },
        action: :record,
        authorize?: false
      )

      conn
      |> put_resp_content_type(e.media_type, nil)
      |> put_resp_header("cache-control", "private, no-store")
      |> put_resp_header("x-content-type-options", "nosniff")
      |> put_resp_header(
        "content-disposition",
        ~s(inline; filename="#{e.kind}-#{e.position + 1}#{extension(e.media_type)}")
      )
      |> send_resp(200, body)
    else
      _ -> send_resp(conn, 404, "Not found")
    end
  end

  def disclose(conn, %{"id" => id, "position" => position} = params) do
    user = conn.assigns[:current_user]

    with %{} <- user,
         {pos, ""} <- Integer.parse(position),
         {:ok, tx} <- Basa.Witness.get_transaction(id, authorize?: false),
         true <- party?(tx, user),
         {:ok, package} <-
           Basa.Witness.Disclosure.build(tx, [pos], share: ticket(params, user, tx.id)) do
      Ash.create!(
        AccessLog,
        %{
          transaction_id: tx.id,
          action: :open,
          actor_id: user.id,
          reason: "disclosure of file #{pos + 1}",
          result: "ok"
        },
        action: :record,
        authorize?: false
      )

      number = tx.id |> String.slice(0, 8) |> String.upcase()

      conn
      |> put_resp_content_type("application/json")
      |> put_resp_header("cache-control", "private, no-store")
      |> put_resp_header(
        "content-disposition",
        ~s(attachment; filename="basa-#{number}-file-#{pos + 1}.json")
      )
      |> send_resp(200, Jason.encode!(package, pretty: true))
    else
      _ -> send_resp(conn, 404, "Not found")
    end
  end

  def recovery_kit(conn, %{"id" => id}) do
    user = conn.assigns[:current_user]

    with %{role: :admin} <- user,
         {:ok, request} <- Ash.get(Basa.Witness.AuthorityRequest, id, actor: user),
         {:ok, kit} <- Basa.Witness.Recovery.kit(request, user) do
      reference = String.replace(request.reference, ~r/[^\w.-]+/u, "_")

      conn
      |> put_resp_content_type("application/json")
      |> put_resp_header("cache-control", "private, no-store")
      |> put_resp_header(
        "content-disposition",
        ~s(attachment; filename="basa-recovery-kit-#{reference}.json")
      )
      |> send_resp(200, Jason.encode!(kit))
    else
      _ -> send_resp(conn, 404, "Not found")
    end
  end

  defp ticket(params, user, scope),
    do: Basa.Witness.Openings.take(params["ticket"], user.id, scope)

  defp act_files(query, nil), do: Ash.Query.filter(query, is_nil(act_id))
  defp act_files(query, act_id), do: Ash.Query.filter(query, act_id == ^act_id)

  defp party?(tx, user) do
    Party
    |> Ash.Query.filter(transaction_id == ^tx.id and user_id == ^user.id)
    |> Ash.exists?(authorize?: false)
  end

  defp extension("application/pdf"), do: ".pdf"
  defp extension("image/jpeg"), do: ".jpg"
  defp extension("image/png"), do: ".png"
  defp extension("image/webp"), do: ".webp"
  defp extension("audio/webm"), do: ".webm"
  defp extension("audio/ogg"), do: ".ogg"
  defp extension("audio/mp4"), do: ".m4a"
  defp extension(_), do: ""
end
