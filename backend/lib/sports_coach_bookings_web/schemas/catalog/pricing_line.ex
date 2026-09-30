defmodule SportsCoachBookingsWeb.Schemas.Catalog.PricingLine do
  @moduledoc "A single line passed to the pricing preview."

  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "PricingLine",
    type: :object,
    properties: %{
      type: %Schema{type: :string, enum: ["package", "drop_in", "product"]},
      ref_id: %Schema{type: :string, format: :uuid},
      unit_price: %Schema{type: :integer},
      quantity: %Schema{type: :integer},
      taxable: %Schema{type: :boolean}
    },
    required: [:type, :ref_id, :unit_price, :quantity]
  })
end
