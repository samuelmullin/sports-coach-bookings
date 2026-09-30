defmodule SportsCoachBookingsWeb.Schemas.Policies.AssignmentRemovalResponse do
  @moduledoc "Result of removing a policy assignment from an offering."

  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "PolicyAssignmentRemovalResponse",
    type: :object,
    properties: %{
      offering_id: %Schema{type: :string, format: :uuid},
      removed: %Schema{type: :integer}
    },
    required: [:offering_id, :removed]
  })
end
