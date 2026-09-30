defmodule SportsCoachBookingsWeb.Schemas.Policies.PolicyListResponse do
  @moduledoc "Paginated list of cancellation policies."

  require OpenApiSpex
  alias OpenApiSpex.Schema
  alias SportsCoachBookingsWeb.Schemas.Policies.PolicyResponse

  OpenApiSpex.schema(%{
    title: "PolicyListResponse",
    type: :object,
    properties: %{
      data: %Schema{type: :array, items: PolicyResponse},
      next_cursor: %Schema{type: :string, nullable: true}
    },
    required: [:data]
  })
end
