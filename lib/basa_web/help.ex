defmodule BasaWeb.Help do
  @groups [
    {:renters, ~w(finding-and-booking contract-and-return)},
    {:owners, ~w(owner-getting-started schedule photos import api-keys)},
    {:everyone, ~w(account)},
    {:admins, ~w(admin)}
  ]

  def groups, do: @groups

  def topics, do: Enum.flat_map(@groups, &elem(&1, 1))

  def page(topic, language) do
    with true <- topic in topics(),
         {:ok, markdown, shown} <- read(topic, language) do
      {title, body} = split_title(markdown)

      html =
        MDEx.to_html!(body,
          extension: [table: true, autolink: true, strikethrough: true],
          render: [unsafe: false]
        )

      {:ok, %{title: title, html: html, language: shown}}
    else
      _ -> :error
    end
  end

  def title(topic, language) do
    case read(topic, language) do
      {:ok, markdown, _} -> markdown |> split_title() |> elem(0)
      _ -> topic
    end
  end

  defp read(topic, language) do
    Enum.find_value([language, "en"], :error, fn lang ->
      case File.read(path(lang, topic)) do
        {:ok, markdown} -> {:ok, markdown, lang}
        _ -> nil
      end
    end)
  end

  defp path(lang, topic), do: Application.app_dir(:basa, "priv/help/#{lang}/#{topic}.md")

  defp split_title(markdown) do
    case String.split(markdown, "\n", parts: 2) do
      ["# " <> title, rest] -> {String.trim(title), rest}
      _ -> {"", markdown}
    end
  end
end
