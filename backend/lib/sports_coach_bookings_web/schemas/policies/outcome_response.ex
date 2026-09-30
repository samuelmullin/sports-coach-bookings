defmodule SportsCoachBookingsWeb.Schemas.Policies.OutcomeResponse do
  @moduledoc "The outcome of evaluating a policy."

  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "PolicyOutcome",
    type: :object,
    properties: %{
      allowed: %Schema{type: :boolean},
      reason: %Schema{type: :string, nullable: true},
      credit_outcome: %Schema{type: :string, enum: ["return", "forfeit"], nullable: true},
      refund_amount: %Schema{
        type: :object,
        nullable: true,
        properties: %{
          amount: %Schema{type: :integer},
          currency: %Schema{type: :string}
        },
        required: [:amount, :currency]
      },
      tier_matched: %Schema{type: :integer, nullable: true}
    },
    required: [:allowed]
  })
end
