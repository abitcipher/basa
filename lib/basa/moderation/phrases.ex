defmodule Basa.Moderation.Phrases do
  @phrases [
    {"gear", "a photo of music equipment"},
    {"gear", "a photo of a guitar amplifier or speakers"},
    {"gear", "a photo of a microphone or headphones"},
    {"gear", "a photo of a camera or lights"},
    {"gear", "a photo of tools or a machine"},
    {"gear", "a photo of furniture"},
    {"room", "a photo of a room"},
    {"room", "a photo of a recording studio"},
    {"room", "a photo of a hall or a stage"},
    {"room", "a photo of an office or a workshop"},
    {"place", "a photo of a building entrance or a street"},
    {"people", "a photo of people"},
    {"text", "a screenshot or a picture with text"},
    {"document", "a photo of a passport or an ID card"},
    {"document", "a photo of a bank card"},
    {"weapon", "a photo of a gun"},
    {"weapon", "a photo of a knife or a weapon"},
    {"drugs", "a photo of drugs or syringes"},
    {"gore", "a photo of blood or an injured body"},
    {"nude", "a photo of a naked person"}
  ]

  def all, do: Enum.map(@phrases, fn {key, text} -> %{key: key, text: text} end)

  def keys, do: @phrases |> Enum.map(&elem(&1, 0)) |> Enum.uniq()
end
