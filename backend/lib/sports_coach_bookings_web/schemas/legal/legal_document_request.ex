defmodule SportsCoachBookingsWeb.Schemas.Legal.LegalDocumentRequest do
  @moduledoc "Create/publish payload for a legal document version."

  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "LegalDocumentRequest",
    type: :object,
    properties: %{
      kind: %Schema{type: :string, description: "e.g. terms or privacy"},
      title: %Schema{type: :string},
      body_markdown: %Schema{type: :string},
      active: %Schema{type: :boolean, nullable: true}
    },
    required: [:kind, :title, :body_markdown]
  })
end
