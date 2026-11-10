defmodule BasaWeb.I18nTest do
  use BasaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Basa.Fixtures

  test "a Ukrainian user gets the Ukrainian UI", %{conn: conn} do
    conn = sign_in(conn, user(%{locale: :uk}))
    {:ok, _view, html} = live(conn, ~p"/my")
    assert html =~ "Мої пропозиції"
    assert html =~ "Нова пропозиція"
  end

  test "?locale= switches the language and is remembered", %{conn: conn} do
    conn = get(conn, ~p"/?locale=de")
    assert html_response(conn, 200) =~ "Was du brauchst, ganz nah"

    conn = get(recycle(conn), ~p"/")
    assert html_response(conn, 200) =~ "Was du brauchst, ganz nah"
  end

  test "language links carry their code for keeping the page's address", %{conn: conn} do
    html = conn |> get(~p"/") |> html_response(200)

    for code <- Basa.I18n.codes() do
      assert html =~ ~s(href="?locale=#{code}" data-locale="#{code}")
    end
  end

  test "?locale= keeps the rest of the address working", %{conn: conn} do
    conn = get(conn, ~p"/?q=mic&locale=uk")
    assert html_response(conn, 200) =~ "lang=\"uk\""
  end

  test "domain errors are translated in the user's language" do
    lessor = user()
    lot = published_lot(lessor, basket(lessor, [item(lessor)]), room(lessor))
    start = DateTime.utc_now() |> DateTime.add(-3600, :second)

    Gettext.with_locale(BasaWeb.Gettext, "de", fn ->
      {:error, error} =
        Basa.Bookings.book(
          %{lot_id: lot.id, starts_at: start, ends_at: DateTime.add(start, 3600)},
          actor: user()
        )

      assert Exception.message(error) =~ "liegt in der Vergangenheit"
    end)
  end

  test "category form labels follow the language" do
    schema = %{
      "properties" => %{
        "mic_type" => %{
          "type" => "string",
          "title" => "Type",
          "enum" => ["dynamic"],
          "x-title" => %{"fr" => "Type de micro"},
          "x-enum-titles" => %{"fr" => %{"dynamic" => "dynamique"}}
        }
      }
    }

    assert [%{label: "Type de micro", enum_labels: %{"dynamic" => "dynamique"}}] =
             Basa.JsonSchema.fields(schema, :fr)

    assert [%{label: "Type", enum_labels: %{}}] = Basa.JsonSchema.fields(schema, :en)
  end
end
