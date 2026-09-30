defmodule SportsCoachBookingsWeb.Schemas.Waivers.PlayerWaiverStatusResponse do
  @moduledoc "A player's required/signed waiver matrix."

  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "PlayerWaiverStatusResponse",
    type: :object,
    properties: %{
      player_id: %Schema{type: :string, format: :uuid},
      waivers: %Schema{
        type: :array,
        items: %Schema{
          type: :object,
          properties: %{
            template_id: %Schema{type: :string, format: :uuid},
            name: %Schema{type: :string},
            version_id: %Schema{type: :string, format: :uuid},
            required: %Schema{type: :boolean},
            signed: %Schema{type: :boolean},
            signed_version_id: %Schema{type: :string, format: :uuid, nullable: true},
            signed_at: %Schema{type: :string, format: :"date-time", nullable: true}
          }
        }
      }
    },
    required: [:player_id, :waivers]
  })
end
