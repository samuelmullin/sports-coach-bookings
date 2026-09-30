defmodule SportsCoachBookingsWeb.Schemas.Legal.LegalDocumentResponse do
  @moduledoc "A legal document including its body."

  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "LegalDocumentResponse",
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      kind: %Schema{type: :string, description: "e.g. terms or privacy"},
      title: %Schema{type: :string},
      body_markdown: %Schema{type: :string},
      version: %Schema{type: :integer},
      active: %Schema{type: :boolean},
      inserted_at: %Schema{type: :string, format: :"date-time", nullable: true},
      updated_at: %Schema{type: :string, format: :"date-time", nullable: true}
    },
    required: [:id, :kind, :title, :body_markdown, :version, :active]
  })
end
