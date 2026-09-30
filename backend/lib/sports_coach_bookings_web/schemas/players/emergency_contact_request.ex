defmodule SportsCoachBookingsWeb.Schemas.Players.EmergencyContactRequest do
  @moduledoc "Create/update payload for an emergency contact."

  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "EmergencyContactRequest",
    type: :object,
    properties: %{
      name: %Schema{type: :string},
      relationship: %Schema{type: :string, nullable: true},
      phone: %Schema{type: :string},
      alt_phone: %Schema{type: :string, nullable: true},
      priority: %Schema{type: :integer, minimum: 1}
    }
  })
end
