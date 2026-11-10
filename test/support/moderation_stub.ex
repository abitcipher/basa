defmodule Basa.ModerationStub do
  @behaviour Basa.Moderation.CheckerApi

  @safe %{
    "nsfw" => 0.02,
    "detectors" => %{"marqo-nsfw-384" => 0.02},
    "clip" => %{"gear" => 0.9, "room" => 0.08, "weapon" => 0.01, "document" => 0.01},
    "level" => 1,
    "models" => ["marqo-nsfw-384@test", "clip-vit-b32-int8@test"],
    "ms" => 1
  }

  def scores(scores), do: Process.put(__MODULE__, Map.merge(@safe, scores))

  @impl true
  def available?, do: true

  @impl true
  def check(_bytes),
    do: Process.get({__MODULE__, :error}) || {:ok, Process.get(__MODULE__, @safe)}

  @impl true
  def status,
    do:
      {:ok,
       %{
         "level" => 1,
         "models" => @safe["models"],
         "preparing" => nil,
         "done" => 0,
         "total" => 0,
         "error" => nil
       }}

  @impl true
  def set_level(level), do: {:ok, %{"level" => 1, "preparing" => level}}
end
