defmodule SportsCoachBookingsWeb.Schemas.Catalog.OfferingRequest do
  @moduledoc "Create/update payload for an offering."

  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "OfferingRequest",
    type: :object,
    properties: %{
      name: %Schema{type: :string},
      slug: %Schema{type: :string, nullable: true},
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
      image_key: %Schema{type: :string, nullable: true}
    }
  })
end
