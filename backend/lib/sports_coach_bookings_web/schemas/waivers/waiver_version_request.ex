defmodule SportsCoachBookingsWeb.Schemas.Waivers.WaiverVersionRequest do
  @moduledoc "Create/update payload for a waiver version body."

  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "WaiverVersionRequest",
    type: :object,
    properties: %{
      body_markdown: %Schema{type: :string}
    },
    required: [:body_markdown]
  })
end
