defmodule SportsCoachBookingsWeb.Portal.BrandingController do
  @moduledoc "Public, cacheable tenant branding for the customer portal."

  use SportsCoachBookingsWeb, :controller
  use OpenApiSpex.ControllerSpecs

  action_fallback SportsCoachBookingsWeb.FallbackController

  alias SportsCoachBookings.Tenancy
  alias SportsCoachBookingsWeb.Schemas.Api
  alias SportsCoachBookingsWeb.Schemas.ErrorResponse

  tags(["portal"])

  operation(:show,
    summary: "Get public tenant branding",
    description: "Theme tokens, asset URLs, and tenant name. Cacheable via ETag.",
    responses: [
      ok: {"Branding", "application/json", Api.public_branding()},
      not_modified: {"Not modified", nil, nil},
      not_found: {"Unknown tenant", "application/json", ErrorResponse}
    ]
  )

  @doc "GET /api/portal/branding"
  def show(conn, _params) do
    tenant = conn.assigns.tenant
    body = Jason.encode!(Tenancy.public_branding(tenant))
    etag = etag(body)

    conn =
      conn
      |> put_resp_header("etag", etag)
      |> put_resp_header("cache-control", "public, max-age=300")

    if etag_matches?(conn, etag) do
      send_resp(conn, 304, "")
    else
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(200, body)
    end
  end

  defp etag(body) do
    digest = :crypto.hash(:sha256, body) |> Base.encode16(case: :lower)
    ~s("#{digest}")
  end

  defp etag_matches?(conn, etag) do
    case get_req_header(conn, "if-none-match") do
      [value | _] -> value == "*" or String.contains?(value, etag)
      _ -> false
    end
  end
end
