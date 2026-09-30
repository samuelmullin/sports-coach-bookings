defmodule SportsCoachBookingsWeb.Schemas.Players.EmergencyContactListResponse do
  @moduledoc "List of a player's emergency contacts."

  require OpenApiSpex
  alias OpenApiSpex.Schema
  alias SportsCoachBookingsWeb.Schemas.Players.EmergencyContactResponse

  OpenApiSpex.schema(%{
    title: "EmergencyContactListResponse",
    type: :object,
    properties: %{
      data: %Schema{type: :array, items: EmergencyContactResponse},
      next_cursor: %Schema{type: :string, nullable: true}
    },
    required: [:data]
  })
end
