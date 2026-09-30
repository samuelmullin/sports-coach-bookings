defmodule SportsCoachBookingsWeb.Schemas.Policies.SimulationRequest do
  @moduledoc "Inputs for the policy simulator."

  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "PolicySimulationRequest",
    type: :object,
    properties: %{
      policy_id: %Schema{type: :string, format: :uuid, nullable: true},
      offering_id: %Schema{type: :string, format: :uuid, nullable: true},
      action: %Schema{
        type: :string,
        enum: ["cancel", "rebook", "no_show", "provider_cancel"],
        nullable: true
      },
      hours_before: %Schema{type: :number, nullable: true},
      payment_method: %Schema{type: :string, enum: ["credits", "paid"], nullable: true},
      amount_paid: %Schema{type: :integer, nullable: true},
      currency: %Schema{type: :string, nullable: true},
      rebook_count: %Schema{type: :integer, nullable: true},
      target_offering_id: %Schema{type: :string, format: :uuid, nullable: true},
      source_offering_id: %Schema{type: :string, format: :uuid, nullable: true}
    }
  })
end
