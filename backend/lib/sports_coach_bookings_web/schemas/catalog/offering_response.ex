defmodule SportsCoachBookingsWeb.Schemas.Catalog.OfferingResponse do
  @moduledoc "An offering (class type)."

  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "OfferingResponse",
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      name: %Schema{type: :string},
      slug: %Schema{type: :string},
      description: %Schema{type: :string, nullable: true},
      format: %Schema{type: :string, enum: ["private", "semi_private", "group"]},
      min_age: %Schema{type: :integer, nullable: true},
      max_age: %Schema{type: :integer, nullable: true},
      duration_minutes: %Schema{type: :integer},
      default_capacity: %Schema{type: :integer},
      credit_cost: %Schema{type: :integer},
      drop_in_price: %Schema{type: :integer, nullable: true},
      taxable: %Schema{type: :boolean},
      bookable_until_minutes_before: %Schema{type: :integer},
      bookable_from_days_ahead: %Schema{type: :integer, nullable: true},
      active: %Schema{type: :boolean},
      position: %Schema{type: :integer},
      image_key: %Schema{type: :string, nullable: true},
      inserted_at: %Schema{type: :string, format: :"date-time", nullable: true},
      updated_at: %Schema{type: :string, format: :"date-time", nullable: true},
      public_enabled: %Schema{type: :boolean},
      public_max_players: %Schema{type: :integer},
      public_players_per_coach: %Schema{type: :integer},
      public_price_tiers: %Schema{type: :object, additionalProperties: true},
      private_enabled: %Schema{type: :boolean},
      private_max_players: %Schema{type: :integer},
      private_players_per_coach: %Schema{type: :integer},
      private_price_tiers: %Schema{type: :object, additionalProperties: true},
      allow_invite_reservations: %Schema{type: :boolean},
      invite_hold_hours: %Schema{type: :integer},
      allow_private_conversion: %Schema{type: :boolean},
      allow_private_requests: %Schema{type: :boolean}
    },
    required: [
      :id,
      :name,
      :slug,
      :format,
      :duration_minutes,
      :active,
      :position,
      :public_enabled,
      :public_max_players,
      :public_players_per_coach,
      :private_enabled,
      :private_max_players,
      :private_players_per_coach,
      :allow_invite_reservations,
      :invite_hold_hours,
      :allow_private_conversion,
      :allow_private_requests
    ]
  })
end
