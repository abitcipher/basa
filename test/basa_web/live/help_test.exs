defmodule BasaWeb.HelpTest do
  use BasaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Basa.Fixtures

  alias BasaWeb.Help

  @first_languages ~w(en uk es)

  test "every topic has a page with a title in English, Ukrainian and Spanish" do
    for topic <- Help.topics(), lang <- @first_languages do
      assert {:ok, %{title: title, html: html, language: ^lang}} = Help.page(topic, lang),
             "#{lang}/#{topic}"

      assert title != "" and html =~ "<"
    end
  end

  test "help pages hold no developer material" do
    internal =
      ~r/Basa\.|BasaWeb|\.ex\b|\.exs\b|lib\/|docs\/dev|priv\/|Ash[A-Z ]|Oban|LiveView|NIF|Rust|Decided on|ONNX|Docker|docker|Mapillary|CLIP/

    for lang <- @first_languages, file <- Path.wildcard("priv/help/#{lang}/*.md") do
      text = File.read!(file)
      refute text =~ internal, "#{file}: #{inspect(Regex.run(internal, text))}"
    end
  end

  test "the list of topics; admin topics only for admins", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/help")
    assert has_element?(view, "#help-finding-and-booking", "Find and book")
    refute has_element?(view, "#help-admin")

    {:ok, view, _} = conn |> sign_in(user(%{role: :admin})) |> live(~p"/help")
    assert has_element?(view, "#help-admin")
  end

  test "a page in Ukrainian or Spanish; other languages see English with a note", %{conn: conn} do
    {:ok, view, _} =
      conn |> get(~p"/help/schedule?locale=uk") |> then(&live(&1, ~p"/help/schedule"))

    assert has_element?(view, "#help-page-schedule h1", "Ваш розклад")
    refute has_element?(view, "#help-in-english")

    {:ok, view, _} =
      build_conn() |> get(~p"/help/schedule?locale=de") |> then(&live(&1, ~p"/help/schedule"))

    assert has_element?(view, "#help-page-schedule h1", "Your schedule")
    assert has_element?(view, "#help-in-english")

    {:ok, view, _} =
      build_conn() |> get(~p"/help/schedule?locale=es") |> then(&live(&1, ~p"/help/schedule"))

    assert has_element?(view, "#help-page-schedule h1", "Tu horario")
    refute has_element?(view, "#help-in-english")
  end

  test "an unknown topic goes back to the list", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/help"}}} = live(conn, ~p"/help/nope")
  end

  test "pages link to the help that explains them", %{conn: conn} do
    {:ok, view, _} = conn |> sign_in(user()) |> live(~p"/my")

    assert has_element?(
             view,
             ~s(a#help-link-owner-getting-started[href="/help/owner-getting-started"])
           )
  end
end
