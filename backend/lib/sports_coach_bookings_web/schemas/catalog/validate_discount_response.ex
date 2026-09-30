defmodule SportsCoachBookingsWeb.Schemas.Catalog.ValidateDiscountResponse do
  @moduledoc "Result of the staff discount validation preview."

  require OpenApiSpex
  alias OpenApiSpex.Schema
  alias SportsCoachBookingsWeb.Schemas.Catalog.{DiscountResponse, PricedLine}

  OpenApiSpex.schema(%{
    title: "ValidateDiscountResponse",
    type: :object,
    properties: %{
      lines: %Schema{type: :array, items: PricedLine},
      discount: %Schema{allOf: [DiscountResponse], nullable: true},
      subtotal: %Schema{type: :integer},
      discount_total: %Schema{type: :integer},
      tax_total: %Schema{type: :integer},
      total: %Schema{type: :integer}
    },
    required: [:lines, :subtotal, :discount_total, :tax_total, :total]
  })
end
