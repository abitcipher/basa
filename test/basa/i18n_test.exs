defmodule Basa.I18nTest do
  use ExUnit.Case, async: true

  @po_dir "priv/gettext"

  defp untranslated(locale, domain) do
    path = Path.join([@po_dir, locale, "LC_MESSAGES", "#{domain}.po"])
    {:ok, po} = Expo.PO.parse_file(path)

    for message <- po.messages,
        blank?(message),
        do: IO.iodata_to_binary(Expo.Message.key(message) |> elem(1))
  end

  defp blank?(%Expo.Message.Singular{msgstr: s}), do: IO.iodata_to_binary(s) == ""

  defp blank?(%Expo.Message.Plural{msgstr: forms}),
    do: Enum.any?(forms, fn {_, s} -> IO.iodata_to_binary(s) == "" end)

  test "every language but English has every message translated, none guessed" do
    for locale <- Basa.I18n.codes() -- ["en"], domain <- ["default", "errors", "contracts"] do
      assert untranslated(locale, domain) == [], "#{locale}/#{domain} has untranslated messages"

      path = Path.join([@po_dir, locale, "LC_MESSAGES", "#{domain}.po"])
      refute File.read!(path) =~ "fuzzy", "#{locale}/#{domain} has guessed (fuzzy) translations"
    end
  end

  test "English, the source language, has no guessed (fuzzy) entries either" do
    for domain <- ["default", "errors", "contracts"] do
      path = Path.join([@po_dir, "en", "LC_MESSAGES", "#{domain}.po"])
      refute File.read!(path) =~ "fuzzy", "en/#{domain} has guessed (fuzzy) entries"
    end
  end

  test "the switcher, user settings and the bot use the same languages" do
    codes = Basa.I18n.codes()
    assert codes == ~w(uk en de fr es it pl ro tr)

    assert Basa.I18n.atoms() ==
             Ash.Resource.Info.attribute(Basa.Accounts.User, :locale).constraints[:one_of]

    assert BasaWeb.Plugs.Locale.locales() == codes
    assert Basa.I18n.supported("es") == "es" and Basa.I18n.supported("ja") == nil
  end

  test "plural forms" do
    n = fn locale, count ->
      Gettext.with_locale(BasaWeb.Gettext, locale, fn ->
        Gettext.ngettext(BasaWeb.Gettext, "1 offer", "%{count} offers", count)
      end)
    end

    assert n.("pl", 1) == "1 oferta" and n.("pl", 3) == "3 oferty" and n.("pl", 5) == "5 ofert"
    assert n.("ro", 1) == "1 ofertă" and n.("ro", 21) == "21 de oferte"
    assert n.("es", 2) == "2 ofertas" and n.("tr", 2) == "2 ilan"
  end
end
