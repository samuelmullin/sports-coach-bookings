defmodule SportsCoachBookingsWeb.Schemas.Catalog.OfferingListResponse do
  @moduledoc "Paginated list of offerings."

  require OpenApiSpex
  alias OpenApiSpex.Schema
  alias SportsCoachBookingsWeb.Schemas.Catalog.OfferingResponse

  OpenApiSpex.schema(%{
    title: "OfferingListResponse",
    type: :object,
    properties: %{
      data: %Schema{type: :array, items: OfferingResponse},
      next_cursor: %Schema{type: :string, nullable: true}
    },
    required: [:data]
  })
end
