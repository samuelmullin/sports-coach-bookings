defmodule SportsCoachBookingsWeb.Schemas.Catalog.VenueRequest do
  @moduledoc "Create/update payload for a venue."

  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "VenueRequest",
    type: :object,
    properties: %{
      name: %Schema{type: :string},
      address_line1: %Schema{type: :string, nullable: true},
      address_line2: %Schema{type: :string, nullable: true},
      city: %Schema{type: :string, nullable: true},
      province: %Schema{type: :string, nullable: true},
      postal_code: %Schema{type: :string, nullable: true},
      country: %Schema{type: :string, nullable: true},
      timezone: %Schema{type: :string, nullable: true},
      notes: %Schema{type: :string, nullable: true},
      map_url: %Schema{type: :string, nullable: true},
      active: %Schema{type: :boolean}
    }
  })
end
