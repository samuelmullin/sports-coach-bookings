defmodule SportsCoachBookingsWeb.Schemas.Players.AuthorizedPickupListResponse do
  @moduledoc "List of a player's authorized pickups."

  require OpenApiSpex
  alias OpenApiSpex.Schema
  alias SportsCoachBookingsWeb.Schemas.Players.AuthorizedPickupResponse

  OpenApiSpex.schema(%{
    title: "AuthorizedPickupListResponse",
    type: :object,
    properties: %{
      data: %Schema{type: :array, items: AuthorizedPickupResponse},
      next_cursor: %Schema{type: :string, nullable: true}
    },
    required: [:data]
  })
end
