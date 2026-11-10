defmodule BasaWeb.Plugs.Locale do
  import Plug.Conn

  @locales Basa.I18n.codes()
  @default "en"

  def locales, do: @locales

  def init(opts), do: opts

  def call(conn, _opts) do
    locale =
      valid(conn.params["locale"]) ||
        valid(get_session(conn, :locale)) ||
        user_locale(conn.assigns[:current_user]) ||
        from_header(get_req_header(conn, "accept-language")) ||
        @default

    Gettext.put_locale(BasaWeb.Gettext, locale)
    put_session(conn, :locale, locale)
  end

  def on_mount(:default, _params, session, socket) do
    Gettext.put_locale(BasaWeb.Gettext, valid(session["locale"]) || @default)
    {:cont, socket}
  end

  defp valid(l) when l in @locales, do: l
  defp valid(_), do: nil

  defp user_locale(%{locale: l}) when not is_nil(l), do: valid(to_string(l))
  defp user_locale(_), do: nil

  defp from_header([header | _]) do
    header
    |> String.split(",")
    |> Enum.map(&(&1 |> String.split(";") |> hd() |> String.trim() |> String.slice(0, 2)))
    |> Enum.find(&(&1 in @locales))
  end

  defp from_header(_), do: nil
end
