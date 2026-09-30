defmodule SportsCoachBookingsWeb.Schemas.Players.PlayerProfileRequest do
  @moduledoc "Create/update payload for a player's profile."

  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "PlayerProfileRequest",
    type: :object,
    properties: %{
      home_club: %Schema{type: :string, nullable: true},
      team: %Schema{type: :string, nullable: true},
      preferred_positions: %Schema{type: :array, items: %Schema{type: :string}, nullable: true},
      dominant_foot: %Schema{type: :string, nullable: true},
      goals: %Schema{type: :string, nullable: true},
      interests: %Schema{type: :array, items: %Schema{type: :string}, nullable: true},
      notes_from_family: %Schema{type: :string, nullable: true}
    }
  })
end
