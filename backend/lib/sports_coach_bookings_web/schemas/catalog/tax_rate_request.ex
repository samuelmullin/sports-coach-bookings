defmodule SportsCoachBookingsWeb.Schemas.Catalog.TaxRateRequest do
  @moduledoc "Create/update payload for a tax rate."

  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "TaxRateRequest",
    type: :object,
    properties: %{
      name: %Schema{type: :string},
      rate_bps: %Schema{type: :integer},
      active: %Schema{type: :boolean}
    }
  })
end
