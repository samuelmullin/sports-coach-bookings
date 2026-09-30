defmodule SportsCoachBookingsWeb.Schemas.Legal.LegalDocumentListResponse do
  @moduledoc "A list of legal documents."

  require OpenApiSpex
  alias OpenApiSpex.Schema
  alias SportsCoachBookingsWeb.Schemas.Legal.LegalDocumentSummaryResponse

  OpenApiSpex.schema(%{
    title: "LegalDocumentListResponse",
    type: :object,
    properties: %{
      data: %Schema{type: :array, items: LegalDocumentSummaryResponse}
    },
    required: [:data]
  })
end
