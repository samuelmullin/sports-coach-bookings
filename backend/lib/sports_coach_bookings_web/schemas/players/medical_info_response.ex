defmodule SportsCoachBookingsWeb.Schemas.Players.MedicalInfoResponse do
  @moduledoc "Decrypted medical info, served only by the medical endpoint."

  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "MedicalInfoResponse",
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      player_id: %Schema{type: :string, format: :uuid},
      allergies: %Schema{type: :string, nullable: true},
      conditions: %Schema{type: :string, nullable: true},
      medications: %Schema{type: :string, nullable: true},
      notes: %Schema{type: :string, nullable: true},
      has_medical_info: %Schema{type: :boolean},
      updated_at: %Schema{type: :string, format: :"date-time", nullable: true}
    },
    required: [:player_id, :has_medical_info]
  })
end
