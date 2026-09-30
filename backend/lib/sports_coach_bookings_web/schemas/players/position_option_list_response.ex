defmodule SportsCoachBookingsWeb.Schemas.Players.PositionOptionListResponse do
  @moduledoc "List of a tenant's position options."

  require OpenApiSpex
  alias OpenApiSpex.Schema
  alias SportsCoachBookingsWeb.Schemas.Players.PositionOptionResponse

  OpenApiSpex.schema(%{
    title: "PositionOptionListResponse",
    type: :object,
    properties: %{
      data: %Schema{type: :array, items: PositionOptionResponse},
      next_cursor: %Schema{type: :string, nullable: true}
    },
    required: [:data]
  })
end
