defmodule SportsCoachBookingsWeb.Schemas.Catalog.PackageResponse do
  @moduledoc "A package."

  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "PackageResponse",
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
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
      offering_ids: %Schema{
        type: :array,
        items: %Schema{type: :string, format: :uuid},
        description: "Eligible offering ids. Empty means the package is valid for any offering."
      },
      inserted_at: %Schema{type: :string, format: :"date-time", nullable: true},
      updated_at: %Schema{type: :string, format: :"date-time", nullable: true}
    },
    required: [:id, :name, :credit_quantity, :price, :active, :visible_in_portal, :position]
  })
end
