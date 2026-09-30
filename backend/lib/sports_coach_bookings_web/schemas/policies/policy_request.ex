defmodule SportsCoachBookingsWeb.Schemas.Policies.PolicyRequest do
  @moduledoc "Create/update payload for a cancellation policy."

  require OpenApiSpex
  alias OpenApiSpex.Schema
  alias SportsCoachBookingsWeb.Schemas.Policies.PolicyRules

  OpenApiSpex.schema(%{
    title: "PolicyRequest",
    type: :object,
    properties: %{
      name: %Schema{type: :string},
      is_default: %Schema{type: :boolean, nullable: true},
      active: %Schema{type: :boolean, nullable: true},
      customer_facing_summary: %Schema{type: :string, nullable: true},
      rules: PolicyRules
    },
    required: [:name, :rules]
  })
end
