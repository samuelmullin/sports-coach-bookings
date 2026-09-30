defmodule SportsCoachBookingsWeb.Schemas.Policies.SimulationResponse do
  @moduledoc "The result of the policy simulator."

  require OpenApiSpex
  alias OpenApiSpex.Schema
  alias SportsCoachBookingsWeb.Schemas.Policies.OutcomeResponse

  OpenApiSpex.schema(%{
    title: "PolicySimulationResponse",
    type: :object,
    properties: %{
      snapshot: %Schema{type: :object, additionalProperties: true},
      outcome: OutcomeResponse
    },
    required: [:snapshot, :outcome]
  })
end
