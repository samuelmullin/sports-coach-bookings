defmodule SportsCoachBookingsWeb.Schemas.Catalog.PackageListResponse do
  @moduledoc "Paginated list of packages."

  require OpenApiSpex
  alias OpenApiSpex.Schema
  alias SportsCoachBookingsWeb.Schemas.Catalog.PackageResponse

  OpenApiSpex.schema(%{
    title: "PackageListResponse",
    type: :object,
    properties: %{
      data: %Schema{type: :array, items: PackageResponse},
      next_cursor: %Schema{type: :string, nullable: true}
    },
    required: [:data]
  })
end
