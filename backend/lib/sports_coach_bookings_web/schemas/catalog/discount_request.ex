defmodule SportsCoachBookingsWeb.Schemas.Catalog.DiscountRequest do
  @moduledoc "Create/update payload for a discount."

  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "DiscountRequest",
    type: :object,
    properties: %{
      code: %Schema{type: :string, nullable: true},
      kind: %Schema{type: :string, enum: ["percent", "fixed"]},
      value: %Schema{type: :integer},
      applies_to: %Schema{type: :string, enum: ["all", "packages", "drop_ins", "products"]},
      starts_at: %Schema{type: :string, format: :"date-time", nullable: true},
      ends_at: %Schema{type: :string, format: :"date-time", nullable: true},
      max_redemptions: %Schema{type: :integer, nullable: true},
      per_household_limit: %Schema{type: :integer, nullable: true},
      min_subtotal: %Schema{type: :integer, nullable: true},
      active: %Schema{type: :boolean},
      targets: %Schema{
        type: :array,
        items: %Schema{
          type: :object,
          properties: %{
            target_type: %Schema{type: :string, enum: ["offering", "package", "product"]},
            target_id: %Schema{type: :string, format: :uuid}
          },
          required: [:target_type, :target_id]
        }
      }
    }
  })
end
