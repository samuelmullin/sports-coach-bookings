defmodule SportsCoachBookingsWeb.Schemas.Catalog.DiscountListResponse do
  @moduledoc "Paginated list of discounts."

  require OpenApiSpex
  alias OpenApiSpex.Schema
  alias SportsCoachBookingsWeb.Schemas.Catalog.DiscountResponse

  OpenApiSpex.schema(%{
    title: "DiscountListResponse",
    type: :object,
    properties: %{
      data: %Schema{type: :array, items: DiscountResponse},
      next_cursor: %Schema{type: :string, nullable: true}
    },
    required: [:data]
  })
end
