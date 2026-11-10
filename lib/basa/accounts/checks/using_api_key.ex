defmodule Basa.Accounts.Checks.UsingApiKey do
  use Ash.Policy.SimpleCheck

  @impl true
  def describe(_), do: "actor is using an API key"

  @impl true
  def match?(%{__metadata__: %{using_api_key?: true}}, _context, _opts), do: true
  def match?(_actor, _context, _opts), do: false
end
