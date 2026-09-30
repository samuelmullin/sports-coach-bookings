defmodule SportsCoachBookingsWeb.Schemas.Players.EmergencyContactResponse do
  @moduledoc "An emergency contact."

  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "EmergencyContactResponse",
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      player_id: %Schema{type: :string, format: :uuid},
      name: %Schema{type: :string},
      relationship: %Schema{type: :string, nullable: true},
      phone: %Schema{type: :string},
      alt_phone: %Schema{type: :string, nullable: true},
      priority: %Schema{type: :integer}
    },
    required: [:id, :player_id, :name, :phone, :priority]
  })
end
