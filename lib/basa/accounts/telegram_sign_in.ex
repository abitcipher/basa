defmodule Basa.Accounts.TelegramSignIn do
  @spec sign_in(map()) :: {:ok, struct()} | {:error, term()}
  def sign_in(%{telegram_id: id} = attrs) when is_integer(id) do
    with {:ok, user} <-
           Basa.Accounts.User
           |> Ash.Changeset.for_create(:sign_in_with_telegram, attrs, authorize?: false)
           |> Ash.create(authorize?: false),
         {:ok, token, _claims} <- AshAuthentication.Jwt.token_for_user(user) do
      {:ok, Ash.Resource.put_metadata(user, :token, token)}
    end
  end

  def find(telegram_id) do
    require Ash.Query

    Basa.Accounts.User
    |> Ash.Query.filter(telegram_id == ^telegram_id)
    |> Ash.read_one(authorize?: false)
  end
end
