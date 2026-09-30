defmodule SportsCoachBookingsWeb.Schemas.Policies.PolicyResponse do
  @moduledoc "A cancellation policy."

  require OpenApiSpex
  alias OpenApiSpex.Schema
  alias SportsCoachBookingsWeb.Schemas.Policies.PolicyRules

  OpenApiSpex.schema(%{
    title: "PolicyResponse",
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      name: %Schema{type: :string},
      is_default: %Schema{type: :boolean},
      version: %Schema{type: :integer},
      active: %Schema{type: :boolean},
      customer_facing_summary: %Schema{type: :string, nullable: true},
      rules: PolicyRules,
      assigned_offering_ids: %Schema{
        type: :array,
        items: %Schema{type: :string, format: :uuid}
      },
      inserted_at: %Schema{type: :string, format: :"date-time", nullable: true},
      updated_at: %Schema{type: :string, format: :"date-time", nullable: true}
    },
    required: [:id, :name, :is_default, :version, :active, :rules]
  })
end
