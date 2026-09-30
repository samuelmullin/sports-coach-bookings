defmodule SportsCoachBookingsWeb.Schemas.Waivers.HouseholdWaiverStatusResponse do
  @moduledoc "The per-player waiver matrix for a household."

  require OpenApiSpex
  alias OpenApiSpex.Schema
  alias SportsCoachBookingsWeb.Schemas.Waivers.PlayerWaiverStatusResponse

  OpenApiSpex.schema(%{
    title: "HouseholdWaiverStatusResponse",
    type: :object,
    properties: %{
      players: %Schema{type: :array, items: PlayerWaiverStatusResponse}
    },
    required: [:players]
  })
end
