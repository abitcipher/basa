defmodule Basa.AI do
  @type suggestion :: %{
          title: String.t(),
          brand: String.t() | nil,
          model: String.t() | nil,
          category_slug: String.t() | nil,
          condition: String.t() | nil,
          confidence: float(),
          notes: String.t() | nil
        }

  @callback recognize(image :: binary(), media_type :: String.t(), opts :: keyword()) ::
              {:ok, [suggestion()]} | {:error, term()}

  def recognize(image, media_type, opts \\ []) do
    if Basa.Services.switched_off?(:ai),
      do: {:error, :disabled},
      else: recognizer().recognize(image, media_type, opts)
  end

  def configured?, do: recognizer() != Basa.AI.Claude or Basa.AI.Claude.api_key() not in [nil, ""]

  def enabled?, do: configured?() and Basa.Services.on?(:ai)

  defp recognizer, do: Application.get_env(:basa, :recognizer, Basa.AI.Claude)
end
