defmodule SportsCoachBookingsWeb.Schemas.Waivers.WaiverTemplateResponse do
  @moduledoc "A waiver template."

  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "WaiverTemplateResponse",
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      name: %Schema{type: :string},
      scope: %Schema{type: :string, enum: ["all_bookings", "offerings"]},
      require_resign_on_new_version: %Schema{type: :boolean},
      active: %Schema{type: :boolean},
      offering_ids: %Schema{type: :array, items: %Schema{type: :string, format: :uuid}},
      inserted_at: %Schema{type: :string, format: :"date-time", nullable: true},
      updated_at: %Schema{type: :string, format: :"date-time", nullable: true}
    },
    required: [:id, :name, :scope, :active]
  })
end
