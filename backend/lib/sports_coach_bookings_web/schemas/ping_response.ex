defmodule SportsCoachBookingsWeb.Schemas.PingResponse do
  @moduledoc "Response for the portal ping endpoint."

  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "PingResponse",
    description: "Health check result including the resolved tenant, if any.",
    type: :object,
    properties: %{
      status: %Schema{type: :string, example: "ok"},
      tenant: %Schema{type: :string, nullable: true, example: "demo"},
      platform: %Schema{type: :boolean}
    },
    required: [:status, :platform],
    example: %{"status" => "ok", "tenant" => "demo", "platform" => false}
  })
end
