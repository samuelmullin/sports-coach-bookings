defmodule SportsCoachBookingsWeb.Schemas.Players.PlayerListResponse do
  @moduledoc "Paginated list of players."

  require OpenApiSpex
  alias OpenApiSpex.Schema
  alias SportsCoachBookingsWeb.Schemas.Players.PlayerResponse

  OpenApiSpex.schema(%{
    title: "PlayerListResponse",
    type: :object,
    properties: %{
      data: %Schema{type: :array, items: PlayerResponse},
      next_cursor: %Schema{type: :string, nullable: true}
    },
    required: [:data]
  })
end
