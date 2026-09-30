defmodule SportsCoachBookingsWeb.Schemas.Legal.LegalDocumentSummaryResponse do
  @moduledoc "A legal document summary without its body."

  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "LegalDocumentSummaryResponse",
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      kind: %Schema{type: :string},
      title: %Schema{type: :string},
      version: %Schema{type: :integer},
      active: %Schema{type: :boolean},
      updated_at: %Schema{type: :string, format: :"date-time", nullable: true}
    },
    required: [:id, :kind, :title, :version, :active]
  })
end
