defmodule Basa.Accounts.User.Changes.FromOAuth do
  use Ash.Resource.Change
  use Gettext, backend: BasaWeb.Gettext

  @impl true
  def change(changeset, _opts, _context) do
    info = Ash.Changeset.get_argument(changeset, :user_info) || %{}

    case attrs(changeset.action.name, info) do
      {:ok, attrs} ->
        Ash.Changeset.change_attributes(changeset, attrs)

      :error ->
        Ash.Changeset.add_error(changeset,
          field: :user_info,
          message: gettext("The sign-in didn't return what BASA needs.")
        )
    end
  end

  @doc false
  def attrs(:register_with_google, %{"email" => email} = info)
      when is_binary(email) and email != "" do
    if info["email_verified"] in [true, "true"],
      do: {:ok, %{email: email, display_name: info["name"]}},
      else: :error
  end

  def attrs(:register_with_facebook, info) do
    case to_id(info["id"] || info["sub"]) do
      nil -> :error
      id -> {:ok, %{facebook_id: id, display_name: info["name"]}}
    end
  end

  def attrs(:register_with_instagram, info) do
    case to_id(info["id"] || info["sub"] || info["user_id"]) do
      nil ->
        :error

      id ->
        username = info["username"] || info["preferred_username"]
        {:ok, %{instagram_id: id, instagram_username: username, display_name: username}}
    end
  end

  def attrs(_, _), do: :error

  defp to_id(id) when is_integer(id), do: Integer.to_string(id)
  defp to_id(id) when is_binary(id) and id != "", do: id
  defp to_id(_), do: nil
end
