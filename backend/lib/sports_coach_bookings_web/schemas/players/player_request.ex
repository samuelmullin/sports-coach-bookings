defmodule SportsCoachBookingsWeb.Schemas.Players.PlayerRequest do
  @moduledoc "Create/update payload for a player."

  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "PlayerRequest",
    type: :object,
    properties: %{
      household_id: %Schema{type: :string, format: :uuid, nullable: true},
      first_name: %Schema{type: :string},
      last_name: %Schema{type: :string},
      preferred_name: %Schema{type: :string, nullable: true},
      date_of_birth: %Schema{type: :string, format: :date},
      is_self: %Schema{type: :boolean, nullable: true},
      photo_key: %Schema{type: :string, nullable: true},
      active: %Schema{type: :boolean, nullable: true},
      no_pickup_restrictions: %Schema{type: :boolean, nullable: true}
    }
  })
end
