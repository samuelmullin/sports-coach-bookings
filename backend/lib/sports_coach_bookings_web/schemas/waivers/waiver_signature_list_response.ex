defmodule SportsCoachBookingsWeb.Schemas.Waivers.WaiverSignatureListResponse do
  @moduledoc "Paginated list of waiver signatures."

  require OpenApiSpex
  alias OpenApiSpex.Schema
  alias SportsCoachBookingsWeb.Schemas.Waivers.WaiverSignatureResponse

  OpenApiSpex.schema(%{
    title: "WaiverSignatureListResponse",
    type: :object,
    properties: %{
      data: %Schema{type: :array, items: WaiverSignatureResponse},
      next_cursor: %Schema{type: :string, nullable: true}
    },
    required: [:data]
  })
end
