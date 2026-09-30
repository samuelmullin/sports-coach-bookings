defmodule SportsCoachBookingsWeb.Schemas.Catalog.TaxRateListResponse do
  @moduledoc "Paginated list of tax rates."

  require OpenApiSpex
  alias OpenApiSpex.Schema
  alias SportsCoachBookingsWeb.Schemas.Catalog.TaxRateResponse

  OpenApiSpex.schema(%{
    title: "TaxRateListResponse",
    type: :object,
    properties: %{
      data: %Schema{type: :array, items: TaxRateResponse},
      next_cursor: %Schema{type: :string, nullable: true}
    },
    required: [:data]
  })
end
