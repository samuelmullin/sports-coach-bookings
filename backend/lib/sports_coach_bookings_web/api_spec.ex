defmodule SportsCoachBookingsWeb.ApiSpec do
  @moduledoc """
  The OpenAPI 3 specification.

  Routes are discovered from the router and grouped by the `platform`, `staff`,
  and `portal` tags (see `docs/conventions.md`). `mix app.openapi.export` writes
  the spec to `docs/openapi.json`, which `pnpm gen:api` consumes.
  """

  alias OpenApiSpex.{Components, Info, OpenApi, Server, Tag}

  @doc "Builds the OpenAPI specification."
  def spec do
    %OpenApi{
      info: %Info{
        title: "SportsCoachBookings API",
        version: "0.1.0",
        description: "Multi-tenant coaching bookings API. JSON only."
      },
      servers: [%Server{url: "https://sportscoachbookings.com"}],
      tags: [
        %Tag{name: "platform", description: "Tenant signup, staff auth, tenant picker"},
        %Tag{name: "staff", description: "Admin and coach API (tenant-scoped)"},
        %Tag{name: "portal", description: "Customer portal API (tenant-scoped)"}
      ],
      components: %Components{schemas: %{}},
      paths: OpenApiSpex.Paths.from_router(SportsCoachBookingsWeb.Router)
    }
    |> OpenApiSpex.resolve_schema_modules()
  end
end
