defmodule SportsCoachBookingsWeb.Schemas.Catalog.VenueResponse do
  @moduledoc "A venue."

  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "VenueResponse",
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      name: %Schema{type: :string},
      address_line1: %Schema{type: :string, nullable: true},
      address_line2: %Schema{type: :string, nullable: true},
      city: %Schema{type: :string, nullable: true},
      province: %Schema{type: :string, nullable: true},
      postal_code: %Schema{type: :string, nullable: true},
      country: %Schema{type: :string, nullable: true},
      timezone: %Schema{type: :string},
      notes: %Schema{type: :string, nullable: true},
      map_url: %Schema{type: :string, nullable: true},
      active: %Schema{type: :boolean},
      inserted_at: %Schema{type: :string, format: :"date-time", nullable: true},
      updated_at: %Schema{type: :string, format: :"date-time", nullable: true}
    },
    required: [:id, :name, :timezone, :active]
  })
end
