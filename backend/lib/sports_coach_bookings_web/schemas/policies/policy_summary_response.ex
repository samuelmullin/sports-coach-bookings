defmodule SportsCoachBookingsWeb.Schemas.Policies.PolicySummaryResponse do
  @moduledoc "The customer-facing cancellation summary for an offering."

  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "PolicySummaryResponse",
    type: :object,
    properties: %{
      offering_id: %Schema{type: :string, format: :uuid},
      policy_id: %Schema{type: :string, format: :uuid, nullable: true},
      policy_name: %Schema{type: :string},
      policy_version: %Schema{type: :integer},
      summary: %Schema{type: :string, nullable: true}
    },
    required: [:offering_id, :policy_name, :policy_version]
  })
end
