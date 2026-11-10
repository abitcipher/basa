defmodule BasaWeb.MediaController do
  use BasaWeb, :controller

  require Ash.Query

  @public ~w(items rooms entrance street stock)

  def show(conn, %{"key" => [folder | _] = parts}) when folder in @public do
    key = Enum.join(parts, "/")
    check = check(key)

    cond do
      hidden?(check) and not may_see_hidden?(conn.assigns[:current_user], check) ->
        send_resp(conn, 404, "Not found")

      true ->
        serve(conn, key, cache(check))
    end
  end

  def show(conn, _params), do: send_resp(conn, 404, "Not found")

  defp serve(conn, key, cache) do
    case Basa.Storage.get(key) do
      {:ok, body, type} ->
        conn
        |> put_resp_content_type(type, nil)
        |> put_resp_header("cache-control", cache)
        |> send_resp(200, body)

      {:error, _} ->
        send_resp(conn, 404, "Not found")
    end
  end

  defp check(key) do
    Basa.Moderation.PhotoCheck
    |> Ash.Query.filter(key == ^key)
    |> Ash.Query.load(:hidden?)
    |> Ash.read_one!(authorize?: false)
  end

  defp hidden?(%{hidden?: true}), do: true
  defp hidden?(_), do: false

  defp may_see_hidden?(%{role: :admin}, _check), do: true
  defp may_see_hidden?(%{id: id}, %{owner_id: id}) when not is_nil(id), do: true
  defp may_see_hidden?(_, _), do: false

  defp cache(%{hidden?: true}), do: "private, no-store"
  defp cache(%{status: :checked}), do: "public, max-age=31536000, immutable"
  defp cache(_), do: "public, max-age=300"
end
