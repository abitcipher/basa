defmodule BasaWeb.AshJsonApiRouter do
  use AshJsonApi.Router,
    domains: [Basa.Catalog, Basa.Import],
    open_api: "/open_api",
    modify_open_api: {__MODULE__, :modify_open_api, []}

  @doc false
  def modify_open_api(spec, _conn, _opts) do
    scheme = %OpenApiSpex.SecurityScheme{
      type: "http",
      scheme: "bearer",
      bearerFormat: "basa_…",
      description:
        "An API key made at /profile (\"API keys\"): Authorization: Bearer basa_…. It acts as its user: categories; that user's own items and offers (lots: make drafts, submit them for review, archive); and, for users with import access, their import sources (crawl a catalogue, import a page; both queued, results under /import/entries). At most 120 requests a minute per key."
    }

    %{
      spec
      | info: %{spec.info | title: "BASA API", version: "1"},
        components: %{spec.components | securitySchemes: %{"bearerAuth" => scheme}}
    }
  end
end
