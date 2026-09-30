defmodule SportsCoachBookingsWeb.Schemas.Catalog.VenueListResponse do
  @moduledoc "Paginated list of venues."

  require OpenApiSpex
  alias OpenApiSpex.Schema
  alias SportsCoachBookingsWeb.Schemas.Catalog.VenueResponse

  OpenApiSpex.schema(%{
    title: "VenueListResponse",
    type: :object,
    properties: %{
      data: %Schema{type: :array, items: VenueResponse},
      next_cursor: %Schema{type: :string, nullable: true}
    },
    required: [:data]
  })
end
