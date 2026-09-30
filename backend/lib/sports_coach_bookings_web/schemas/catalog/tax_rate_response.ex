defmodule SportsCoachBookingsWeb.Schemas.Catalog.TaxRateResponse do
  @moduledoc "A tenant tax rate."

  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "TaxRateResponse",
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      name: %Schema{type: :string},
      rate_bps: %Schema{type: :integer},
      active: %Schema{type: :boolean},
      inserted_at: %Schema{type: :string, format: :"date-time", nullable: true},
      updated_at: %Schema{type: :string, format: :"date-time", nullable: true}
    },
    required: [:id, :name, :rate_bps, :active]
  })
end
