defmodule SportsCoachBookingsWeb.Schemas.Catalog.PackageRequest do
  @moduledoc "Create/update payload for a package."

  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "PackageRequest",
    type: :object,
    properties: %{
      name: %Schema{type: :string},
      description: %Schema{type: :string, nullable: true},
      credit_quantity: %Schema{type: :integer},
      validity_days: %Schema{type: :integer, nullable: true},
      price: %Schema{type: :integer},
      taxable: %Schema{type: :boolean},
      per_household_limit: %Schema{type: :integer, nullable: true},
      active: %Schema{type: :boolean},
      visible_in_portal: %Schema{type: :boolean},
      position: %Schema{type: :integer},
      offering_ids: %Schema{type: :array, items: %Schema{type: :string, format: :uuid}}
    }
  })
end
