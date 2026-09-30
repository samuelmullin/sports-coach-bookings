defmodule SportsCoachBookingsWeb.Schemas.Catalog.PricedLine do
  @moduledoc "A line after pricing."

  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "PricedLine",
    type: :object,
    properties: %{
      type: %Schema{type: :string, enum: ["package", "drop_in", "product"]},
      ref_id: %Schema{type: :string, format: :uuid},
      unit_price: %Schema{type: :integer},
      quantity: %Schema{type: :integer},
      taxable: %Schema{type: :boolean},
      amount: %Schema{type: :integer},
      discount_amount: %Schema{type: :integer},
      tax_amount: %Schema{type: :integer},
      line_total: %Schema{type: :integer}
    },
    required: [:type, :ref_id, :amount, :discount_amount, :tax_amount, :line_total]
  })
end
