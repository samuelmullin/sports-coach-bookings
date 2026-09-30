defmodule SportsCoachBookingsWeb.Schemas.Players.MedicalInfoRequest do
  @moduledoc "Create/update payload for a player's encrypted medical info."

  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "MedicalInfoRequest",
    type: :object,
    properties: %{
      allergies: %Schema{type: :string, nullable: true},
      conditions: %Schema{type: :string, nullable: true},
      medications: %Schema{type: :string, nullable: true},
      notes: %Schema{type: :string, nullable: true}
    }
  })
end
