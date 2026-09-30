defmodule SportsCoachBookingsWeb.Schemas.Catalog.DiscountResponse do
  @moduledoc "A discount."

  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "DiscountResponse",
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
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
      inserted_at: %Schema{type: :string, format: :"date-time", nullable: true},
      updated_at: %Schema{type: :string, format: :"date-time", nullable: true}
    },
    required: [:id, :kind, :value, :applies_to, :active]
  })
end
