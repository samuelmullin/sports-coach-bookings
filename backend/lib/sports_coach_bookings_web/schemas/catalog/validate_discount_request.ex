defmodule SportsCoachBookingsWeb.Schemas.Catalog.ValidateDiscountRequest do
  @moduledoc "Payload for the staff discount validation preview."

  require OpenApiSpex
  alias OpenApiSpex.Schema
  alias SportsCoachBookingsWeb.Schemas.Catalog.PricingLine

  OpenApiSpex.schema(%{
    title: "ValidateDiscountRequest",
    type: :object,
    properties: %{
      lines: %Schema{type: :array, items: PricingLine},
      discount_code: %Schema{type: :string, nullable: true},
      household_id: %Schema{type: :string, format: :uuid, nullable: true}
    },
    required: [:lines]
  })
end
