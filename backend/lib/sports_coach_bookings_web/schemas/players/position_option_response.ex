defmodule SportsCoachBookingsWeb.Schemas.Players.PositionOptionResponse do
  @moduledoc "A tenant-configurable position option."

  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "PositionOptionResponse",
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      code: %Schema{type: :string},
      label: %Schema{type: :string, nullable: true},
      position: %Schema{type: :integer},
      active: %Schema{type: :boolean}
    },
    required: [:id, :code, :position, :active]
  })
end
