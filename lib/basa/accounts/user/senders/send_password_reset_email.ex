defmodule Basa.Accounts.User.Senders.SendPasswordResetEmail do
  use AshAuthentication.Sender
  use BasaWeb, :verified_routes

  import Swoosh.Email

  alias Basa.Mailer

  @impl true
  def send(user, token, _) do
    new()
    |> from({"noreply", "noreply@example.com"})
    |> to(to_string(user.email))
    |> subject("Reset your password")
    |> html_body(body(token: token))
    |> Mailer.deliver_if_on()
  end

  defp body(params) do
    url = url(~p"/password-reset/#{params[:token]}")

    """
    <p>Click this link to reset your password:</p>
    <p><a href="#{url}">#{url}</a></p>
    """
  end
end
