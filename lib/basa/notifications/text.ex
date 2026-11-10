defmodule Basa.Notifications.Text do
  use Gettext, backend: BasaWeb.Gettext

  def booking(booking, event, locale) do
    Gettext.with_locale(BasaWeb.Gettext, to_string(locale || :en), fn ->
      when_text = Calendar.strftime(booking.starts_at, "%Y-%m-%d %H:%M UTC")

      case event do
        :created ->
          gettext("New booking for “%{lot}” on %{when}.", lot: booking.lot.title, when: when_text)

        :confirmed ->
          gettext("Your booking for “%{lot}” on %{when} is confirmed.",
            lot: booking.lot.title,
            when: when_text
          )

        :declined ->
          gettext("Your booking request for “%{lot}” was declined.", lot: booking.lot.title)

        :cancelled ->
          gettext("The booking for “%{lot}” on %{when} was cancelled.",
            lot: booking.lot.title,
            when: when_text
          )

        _ ->
          gettext("Booking update for “%{lot}”.", lot: booking.lot.title)
      end
    end)
  end
end
