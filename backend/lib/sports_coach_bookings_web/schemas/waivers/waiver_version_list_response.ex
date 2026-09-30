defmodule SportsCoachBookingsWeb.Schemas.Waivers.WaiverVersionListResponse do
  @moduledoc "Paginated list of waiver versions."

  require OpenApiSpex
  alias OpenApiSpex.Schema
  alias SportsCoachBookingsWeb.Schemas.Waivers.WaiverVersionResponse

  OpenApiSpex.schema(%{
    title: "WaiverVersionListResponse",
    type: :object,
    properties: %{
      data: %Schema{type: :array, items: WaiverVersionResponse},
      next_cursor: %Schema{type: :string, nullable: true}
    },
    required: [:data]
  })
end
