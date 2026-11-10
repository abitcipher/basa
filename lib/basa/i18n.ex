defmodule Basa.I18n do
  use Gettext, backend: BasaWeb.Gettext

  @locales [
    {"uk", "UA", "Українська"},
    {"en", "EN", "English"},
    {"de", "DE", "Deutsch"},
    {"fr", "FR", "Français"},
    {"es", "ES", "Español"},
    {"it", "IT", "Italiano"},
    {"pl", "PL", "Polski"},
    {"ro", "RO", "Română"},
    {"tr", "TR", "Türkçe"}
  ]

  @codes Enum.map(@locales, &elem(&1, 0))

  def codes, do: @codes

  def atoms, do: Enum.map(@codes, &String.to_atom/1)

  def locales, do: @locales

  def supported(code) when code in @codes, do: code
  def supported(_), do: nil

  def t(template, vars \\ []) do
    Gettext.dgettext(BasaWeb.Gettext, "errors", template, vars)
  end

  @doc false
  def known_messages do
    [
      dgettext_noop("errors", "is required"),
      dgettext_noop("errors", "pick one handover time"),
      dgettext_noop("errors", "is already reserved by a buyer"),
      dgettext_noop("errors", "is invalid"),
      dgettext_noop("errors", "must be present"),
      dgettext_noop("errors", "has already been taken"),
      dgettext_noop("errors", "length must be greater than or equal to %{min}"),
      dgettext_noop("errors", "length must be less than or equal to %{max}"),
      dgettext_noop("errors", "must be greater than or equal to %{min}"),
      dgettext_noop("errors", "must be less than or equal to %{max}"),
      dgettext_noop("errors", "atom must be one of %{atom_list}, got: %{value}"),
      dgettext_noop("errors", "this slot was just taken"),
      dgettext_noop("errors", "is not yours"),
      dgettext_noop("errors", "must be one of your own"),
      dgettext_noop("errors", "is not available for booking"),
      dgettext_noop("errors", "is your own offer"),
      dgettext_noop("errors", "is not available"),
      dgettext_noop("errors", "is required for slot pricing"),
      dgettext_noop("errors", "must be at least the minimum"),
      dgettext_noop("errors", "is not a known time zone"),
      dgettext_noop("errors", "can no longer be cancelled (%{hours} h rule)"),
      dgettext_noop("errors", "must be after the start"),
      dgettext_noop("errors", "is in the past"),
      dgettext_noop("errors", "must be at least %{hours} h from now"),
      dgettext_noop("errors", "must cover whole %{minutes}-minute slots"),
      dgettext_noop("errors", "is shorter than the minimum of %{units}"),
      dgettext_noop("errors", "is longer than the maximum of %{units}"),
      dgettext_noop("errors", "is outside the opening hours"),
      dgettext_noop("errors", "card payments are available in UAH, USD and EUR"),
      dgettext_noop("errors", "can't be more than the booking"),
      dgettext_noop("errors", "payments are unavailable right now, please try later"),
      dgettext_noop("errors", "lot_empty"),
      dgettext_noop("errors", "lot_title_short"),
      dgettext_noop("errors", "lot_price_zero"),
      dgettext_noop("errors", "lot_room_location"),
      dgettext_noop("errors", "lot_high_value"),
      dgettext_noop("errors", "lot_photos_checked"),
      dgettext_noop("errors", "photo_nudity_clear"),
      dgettext_noop("errors", "photo_nudity_possible"),
      dgettext_noop("errors", "photo_harm"),
      dgettext_noop("errors", "photo_documents")
    ]
  end
end
