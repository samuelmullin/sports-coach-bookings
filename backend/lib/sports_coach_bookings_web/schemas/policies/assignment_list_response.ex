defmodule SportsCoachBookingsWeb.Schemas.Policies.AssignmentListResponse do
  @moduledoc "A list of offering → policy assignments."

  require OpenApiSpex
  alias OpenApiSpex.Schema
  alias SportsCoachBookingsWeb.Schemas.Policies.AssignmentResponse

  OpenApiSpex.schema(%{
    title: "PolicyAssignmentListResponse",
    type: :object,
    properties: %{
      data: %Schema{type: :array, items: AssignmentResponse}
    },
    required: [:data]
  })
end
