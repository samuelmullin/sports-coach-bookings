defmodule SportsCoachBookingsWeb.Schemas.Players.AuthorizedPickupResponse do
  @moduledoc "An authorized pickup."

  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "AuthorizedPickupResponse",
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      player_id: %Schema{type: :string, format: :uuid},
      name: %Schema{type: :string},
      relationship: %Schema{type: :string, nullable: true},
      phone: %Schema{type: :string, nullable: true},
      notes: %Schema{type: :string, nullable: true}
    },
    required: [:id, :player_id, :name]
  })
end
