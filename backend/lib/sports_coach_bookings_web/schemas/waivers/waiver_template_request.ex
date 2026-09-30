defmodule SportsCoachBookingsWeb.Schemas.Waivers.WaiverTemplateRequest do
  @moduledoc "Create/update payload for a waiver template."

  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "WaiverTemplateRequest",
    type: :object,
    properties: %{
      name: %Schema{type: :string},
      scope: %Schema{type: :string, enum: ["all_bookings", "offerings"]},
      require_resign_on_new_version: %Schema{type: :boolean, nullable: true},
      active: %Schema{type: :boolean, nullable: true},
      offering_ids: %Schema{
        type: :array,
        items: %Schema{type: :string, format: :uuid},
        nullable: true
      }
    },
    required: [:name, :scope]
  })
end
