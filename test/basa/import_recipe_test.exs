defmodule Basa.ImportRecipeTest do
  use Basa.DataCase, async: true

  alias Basa.Import.{Charset, Detect, Recipe, Selector}

  @base "http://shop.example/p/101"

  setup do
    html =
      "test/support/fixtures/import/shop_table_cp1251.html"
      |> File.read!()
      |> Charset.to_utf8(nil)

    %{html: html, result: html |> Detect.page(@base) |> Map.put(:html, html)}
  end

  defp chain(nodes), do: [%{tag: "html"}, %{tag: "body"} | nodes]

  defp price_span,
    do:
      chain([
        %{tag: "table", nth: 2},
        %{tag: "tbody", nth: 1},
        %{tag: "tr", nth: 5},
        %{tag: "td", nth: 2},
        %{tag: "span", nth: 1}
      ])

  describe "picking a value" do
    test "next to a label, the label rule comes first, then a checked CSS path", %{html: html} do
      [first | rest] = Selector.suggest(html, %{chain: price_span(), text: "42 900 грн."})

      assert first.rule == %{from: :spec, label: "Ціна"}
      assert first.value == "42 900 грн."

      assert %{rule: %{from: :css, selector: selector}} = List.last(rest)

      assert selector ==
               "body > table:nth-of-type(2) tr:nth-of-type(5) > td:nth-of-type(2) > span:nth-of-type(1)"
    end

    test "a picture: from the nearest id, giving its address", %{html: html} do
      picked = %{
        chain:
          chain([
            %{tag: "div", id: "gallery", nth: 1},
            %{tag: "a", nth: 2},
            %{tag: "img", nth: 1}
          ]),
        src: "/img/p_101_small.2.jpg"
      }

      rules = Selector.suggest(html, picked)

      assert %{rule: %{selector: "#gallery a:nth-of-type(2) > img:nth-of-type(1)", attr: "src"}} =
               hd(rules)

      assert hd(rules).value == "/img/p_101_small.2.jpg"
    end

    test "nothing is suggested for a description that matches nothing", %{html: html} do
      assert Selector.suggest(html, %{chain: price_span(), text: "something else"}) == []
      assert Selector.suggest(html, %{chain: []}) == []
    end

    test "generated ids and classes are not trusted", %{html: _} do
      html = ~s(<div id="item-48213"><span class="css-1x2y price">10 €</span></div>)

      picked = %{
        chain: [
          %{tag: "html"},
          %{tag: "body"},
          %{tag: "div", id: "item-48213", nth: 1},
          %{tag: "span", classes: ["css-1x2y", "price"], nth: 1}
        ],
        text: "10 €"
      }

      selectors = for %{rule: %{from: :css, selector: s}} <- Selector.suggest(html, picked), do: s
      assert "span.price" in selectors
      refute Enum.any?(selectors, &(&1 =~ "48213" or &1 =~ "css-1x2y"))
    end
  end

  describe "recipes" do
    test "rules fill and replace what auto-detect found", %{result: result} do
      recipe =
        Recipe.load(%{
          "fields" => %{
            "price" => %{"from" => "spec", "label" => "ціна"},
            "category" => %{"from" => "css", "selector" => "#menu a:nth-of-type(1)"},
            "photos" => %{"from" => "css", "selector" => "#gallery a:has(img)", "attr" => "href"},
            "nonsense" => %{"from" => "css", "selector" => "h1"},
            "model" => %{"from" => "teleport"}
          }
        })

      assert Map.keys(recipe.fields) |> Enum.sort() == [:category, :photos, :price]

      {:ok, %{fields: f, sources: s, skip: false}} = Recipe.apply(recipe, result, @base)
      assert Decimal.equal?(f.price, 42_900) and f.currency == "UAH"
      assert f.category == "Головна"
      assert s.category == :recipe

      assert f.photos == [
               "http://shop.example/img/p_101_big.1.jpg",
               "http://shop.example/img/p_101_big.2.jpg"
             ]

      assert f.brand == "Fender"
    end

    test "a JDM graph transforms the result and can skip a page", %{result: result} do
      graph = %{
        "nodes" => [
          %{
            "id" => "in",
            "type" => "inputNode",
            "name" => "Request",
            "position" => %{"x" => 0, "y" => 0}
          },
          %{
            "id" => "map",
            "type" => "expressionNode",
            "name" => "Map",
            "position" => %{"x" => 200, "y" => 0},
            "content" => %{
              "expressions" => [
                %{
                  "id" => "e1",
                  "key" => "category",
                  "value" => "fields.brand == 'Fender' ? 'guitar-amps' : null"
                },
                %{"id" => "e2", "key" => "name", "value" => "fields.brand + ' ' + fields.model"},
                %{"id" => "e3", "key" => "price", "value" => "fields.price - 900"},
                %{"id" => "e4", "key" => "skip", "value" => "specs['Наявність'] != 'є'"}
              ]
            }
          },
          %{
            "id" => "out",
            "type" => "outputNode",
            "name" => "Response",
            "position" => %{"x" => 400, "y" => 0}
          }
        ],
        "edges" => [
          %{"id" => "a", "sourceId" => "in", "targetId" => "map", "type" => "edge"},
          %{"id" => "b", "sourceId" => "map", "targetId" => "out", "type" => "edge"}
        ]
      }

      recipe = Recipe.load(%{"fields" => %{}, "rules" => graph})
      assert {:ok, %{fields: f, sources: s, skip: false}} = Recipe.apply(recipe, result, @base)
      assert f.category == "guitar-amps" and s.category == :rules
      assert f.name == "Fender Twin Reverb"
      assert Decimal.equal?(f.price, 42_000)

      sold = %{
        result
        | specs: List.keyreplace(result.specs, "Наявність", 0, {"Наявність", "немає"})
      }

      assert {:ok, %{skip: true}} = Recipe.apply(recipe, sold, @base)
    end

    test "stored and loaded, a recipe stays the same" do
      recipe =
        Recipe.load(%{
          "fields" => %{
            "brand" => %{"from" => "spec", "label" => "Виробник"},
            "photos" => %{"from" => "css", "selector" => "#g a", "attr" => "href"}
          }
        })

      assert recipe |> Recipe.dump() |> Recipe.load() == recipe
    end
  end
end
