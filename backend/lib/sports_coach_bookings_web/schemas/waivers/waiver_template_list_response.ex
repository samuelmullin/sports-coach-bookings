defmodule SportsCoachBookingsWeb.Schemas.Waivers.WaiverTemplateListResponse do
  @moduledoc "Paginated list of waiver templates."

  require OpenApiSpex
  alias OpenApiSpex.Schema
  alias SportsCoachBookingsWeb.Schemas.Waivers.WaiverTemplateResponse

  OpenApiSpex.schema(%{
    title: "WaiverTemplateListResponse",
    type: :object,
    properties: %{
      data: %Schema{type: :array, items: WaiverTemplateResponse},
      next_cursor: %Schema{type: :string, nullable: true}
    },
    required: [:data]
  })
end
