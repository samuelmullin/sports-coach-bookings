defmodule SportsCoachBookingsWeb.Schemas.Players.AuthorizedPickupRequest do
  @moduledoc "Create/update payload for an authorized pickup."

  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "AuthorizedPickupRequest",
    type: :object,
    properties: %{
      name: %Schema{type: :string},
      relationship: %Schema{type: :string, nullable: true},
      phone: %Schema{type: :string, nullable: true},
      notes: %Schema{type: :string, nullable: true}
    }
  })
end
