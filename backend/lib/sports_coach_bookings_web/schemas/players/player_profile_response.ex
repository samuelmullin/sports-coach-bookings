defmodule SportsCoachBookingsWeb.Schemas.Players.PlayerProfileResponse do
  @moduledoc "A player's sporting profile."

  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "PlayerProfileResponse",
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      player_id: %Schema{type: :string, format: :uuid},
      home_club: %Schema{type: :string, nullable: true},
      team: %Schema{type: :string, nullable: true},
      preferred_positions: %Schema{type: :array, items: %Schema{type: :string}},
      dominant_foot: %Schema{type: :string, nullable: true},
      goals: %Schema{type: :string, nullable: true},
      interests: %Schema{type: :array, items: %Schema{type: :string}},
      notes_from_family: %Schema{type: :string, nullable: true},
      inserted_at: %Schema{type: :string, format: :"date-time", nullable: true},
      updated_at: %Schema{type: :string, format: :"date-time", nullable: true}
    },
    required: [:id, :player_id]
  })
end
