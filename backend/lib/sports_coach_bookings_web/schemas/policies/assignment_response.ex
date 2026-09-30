defmodule SportsCoachBookingsWeb.Schemas.Policies.AssignmentResponse do
  @moduledoc "An offering → policy assignment."

  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "PolicyAssignmentResponse",
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      offering_id: %Schema{type: :string, format: :uuid},
      cancellation_policy_id: %Schema{type: :string, format: :uuid},
      inserted_at: %Schema{type: :string, format: :"date-time", nullable: true},
      updated_at: %Schema{type: :string, format: :"date-time", nullable: true}
    },
    required: [:id, :offering_id, :cancellation_policy_id]
  })
end
