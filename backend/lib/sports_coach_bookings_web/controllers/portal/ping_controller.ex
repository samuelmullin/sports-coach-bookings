defmodule SportsCoachBookingsWeb.Portal.PingController do
  @moduledoc """
  Smoke-test endpoint: returns the resolved tenant slug.

  Used by the WP-00 acceptance checks and uptime probes.
  """

  use SportsCoachBookingsWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias SportsCoachBookingsWeb.Schemas.PingResponse

  tags(["portal"])

  operation(:show,
    summary: "Ping",
    description: "Returns the tenant resolved from the request host.",
    responses: [ok: {"Ping result", "application/json", PingResponse}]
  )

  @doc "GET /api/portal/ping"
  def show(conn, _params) do
    tenant = conn.assigns[:tenant]

    json(conn, %{
      status: "ok",
      tenant: tenant && tenant.slug,
      platform: is_nil(tenant)
    })
  end
end
