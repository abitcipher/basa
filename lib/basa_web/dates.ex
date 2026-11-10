defmodule BasaWeb.Dates do
  use Gettext, backend: BasaWeb.Gettext

  def weekday_short(1), do: gettext("Mon")
  def weekday_short(2), do: gettext("Tue")
  def weekday_short(3), do: gettext("Wed")
  def weekday_short(4), do: gettext("Thu")
  def weekday_short(5), do: gettext("Fri")
  def weekday_short(6), do: gettext("Sat")
  def weekday_short(7), do: gettext("Sun")

  def weekday(1), do: gettext("Monday")
  def weekday(2), do: gettext("Tuesday")
  def weekday(3), do: gettext("Wednesday")
  def weekday(4), do: gettext("Thursday")
  def weekday(5), do: gettext("Friday")
  def weekday(6), do: gettext("Saturday")
  def weekday(7), do: gettext("Sunday")

  def format(date_or_time, pattern) do
    Calendar.strftime(date_or_time, pattern,
      abbreviated_day_of_week_names: &weekday_short/1,
      day_of_week_names: &weekday/1
    )
  end
end
