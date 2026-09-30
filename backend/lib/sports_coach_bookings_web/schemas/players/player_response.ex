defmodule SportsCoachBookingsWeb.Schemas.Players.PlayerResponse do
  @moduledoc "A player. Never contains medical values."

  require OpenApiSpex
  alias OpenApiSpex.Schema
  alias SportsCoachBookingsWeb.Schemas.Players.PlayerProfileResponse

  OpenApiSpex.schema(%{
    title: "PlayerResponse",
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      household_id: %Schema{type: :string, format: :uuid},
      first_name: %Schema{type: :string},
      last_name: %Schema{type: :string},
      preferred_name: %Schema{type: :string, nullable: true},
      date_of_birth: %Schema{type: :string, format: :date},
      age: %Schema{type: :integer},
      is_self: %Schema{type: :boolean},
      photo_key: %Schema{type: :string, nullable: true},
      active: %Schema{type: :boolean},
      no_pickup_restrictions: %Schema{type: :boolean},
      has_medical_info: %Schema{type: :boolean, nullable: true},
      profile: %Schema{allOf: [PlayerProfileResponse], nullable: true},
      emergency_contacts: %Schema{
        type: :array,
        items: %Schema{type: :object},
        nullable: true
      },
      authorized_pickups: %Schema{
        type: :array,
        items: %Schema{type: :object},
        nullable: true
      },
      inserted_at: %Schema{type: :string, format: :"date-time", nullable: true},
      updated_at: %Schema{type: :string, format: :"date-time", nullable: true}
    },
    required: [:id, :household_id, :first_name, :last_name, :date_of_birth, :active]
  })
end
