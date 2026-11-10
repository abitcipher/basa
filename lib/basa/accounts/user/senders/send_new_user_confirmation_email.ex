defmodule Basa.Accounts.User.Senders.SendNewUserConfirmationEmail do
  use AshAuthentication.Sender
  use BasaWeb, :verified_routes

  import Swoosh.Email

  alias Basa.Mailer

  @impl true
  def send(user, token, opts) do
    new()
    |> from({"noreply", "noreply@example.com"})
    |> to(to_string(user.email))
    |> subject(subject(opts))
    |> html_body(body(token, opts))
    |> Mailer.deliver_if_on()
  end

  defp subject(opts) do
    case opts[:confirmation_type] do
      :identity_link -> "Confirm linking your #{opts[:provider]} login"
      _ -> "Confirm your email address"
    end
  end

  defp body(token, opts) do
    url = url(~p"/confirm_new_user/#{token}")

    case opts[:confirmation_type] do
      :identity_link ->
        """
        <p>Someone signed in with #{opts[:provider]} using your email address
        and wants to link it to your account.</p>
        <p>If this was you, confirm here: <a href="#{url}">#{url}</a></p>
        <p>If it wasn't you, ignore this email - nothing has changed.</p>
        """

      _ ->
        """
        <p>Click this link to confirm your email:</p>
        <p><a href="#{url}">#{url}</a></p>
        """
    end
  end
end
