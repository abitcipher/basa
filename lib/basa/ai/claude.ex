defmodule Basa.AI.Claude do
  @behaviour Basa.AI
  require Logger

  @url "https://api.anthropic.com/v1/messages"
  @model "claude-opus-5-5"

  def api_key, do: Application.get_env(:basa, :anthropic_api_key)

  @impl true
  def recognize(image, media_type, opts \\ []) do
    categories = Keyword.get(opts, :category_slugs, [])

    case api_key() do
      key when key in [nil, ""] -> {:error, :disabled}
      key -> request(key, image, media_type, categories)
    end
  end

  defp request(key, image, media_type, categories) do
    body = %{
      model: @model,
      max_tokens: 4096,
      fallbacks: "default",
      output_config: %{effort: "low", format: %{type: "json_schema", schema: schema(categories)}},
      system: system_prompt(),
      messages: [
        %{
          role: "user",
          content: [
            %{
              type: "image",
              source: %{type: "base64", media_type: media_type, data: Base.encode64(image)}
            },
            %{type: "text", text: "List the rentable items in this photo."}
          ]
        }
      ]
    }

    Req.post(@url,
      json: body,
      headers: [
        {"x-api-key", key},
        {"anthropic-version", "2026-10-21"},
        {"anthropic-beta", "server-side-fallback-2026-07-01"}
      ],
      receive_timeout: 120_000,
      retry: :transient
    )
    |> handle()
  end

  defp handle({:ok, %{status: 200, body: %{"stop_reason" => "refusal"}}}), do: {:error, :refused}

  defp handle({:ok, %{status: 200, body: %{"content" => content}}}) do
    text =
      Enum.find_value(content, fn
        %{"type" => "text", "text" => t} -> t
        _ -> nil
      end)

    with text when is_binary(text) <- text,
         {:ok, %{"items" => items}} <- Jason.decode(text) do
      {:ok, Enum.map(items, &to_suggestion/1)}
    else
      _ -> {:error, :unexpected_response}
    end
  end

  defp handle({:ok, %{status: status, body: body}}) do
    Logger.warning("Claude recognition failed: #{status} #{inspect(body)}")
    {:error, {:http, status}}
  end

  defp handle({:error, error}), do: {:error, error}

  defp to_suggestion(item) do
    %{
      title: item["title"],
      brand: blank_to_nil(item["brand"]),
      model: blank_to_nil(item["model"]),
      category_slug: blank_to_nil(item["category_slug"]),
      condition: item["condition"],
      confidence: item["confidence"] || 0.0,
      notes: blank_to_nil(item["notes"])
    }
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(v), do: v

  defp system_prompt do
    """
    You help people list items for rent on BASA, a rental platform. From a photo, \
    identify each distinct rentable item: studio and music gear, professional or \
    repair tools, clothing, or similar equipment.

    Read brand and model from visible labels, logos and characteristic design. \
    Equipment in a given setting tends to be similar (a recording studio usually \
    has a mixing console, monitors, microphones, an audio interface), which can \
    help, but report only what the photo supports. When brand or model is not \
    readable, leave it empty rather than guessing, and lower the confidence.

    Confidence is 0 to 1: how sure you are about brand and model together. \
    The owner reviews every suggestion before anything is saved.
    """
  end

  defp schema(categories) do
    category =
      if categories == [],
        do: %{type: "string"},
        else: %{type: "string", enum: categories ++ [""]}

    %{
      type: "object",
      additionalProperties: false,
      required: ["items"],
      properties: %{
        items: %{
          type: "array",
          items: %{
            type: "object",
            additionalProperties: false,
            required: [
              "title",
              "brand",
              "model",
              "category_slug",
              "condition",
              "confidence",
              "notes"
            ],
            properties: %{
              title: %{
                type: "string",
                description: "Short listing title, e.g. \"Shure SM7B dynamic microphone\""
              },
              brand: %{type: "string"},
              model: %{type: "string"},
              category_slug: category,
              condition: %{type: "string", enum: ["new", "excellent", "good", "fair", "worn"]},
              confidence: %{type: "number"},
              notes: %{type: "string", description: "Anything the owner should check, or empty"}
            }
          }
        }
      }
    }
  end
end
