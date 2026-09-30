defmodule SportsCoachBookings.Security.SecurityHeadersTest do
  @moduledoc "WP-19: security headers are present on every response."

  use SportsCoachBookingsWeb.ConnCase, async: true

  test "API responses carry the hardening headers", %{conn: conn} do
    conn = get(conn, "/health")

    assert get_resp_header(conn, "x-content-type-options") == ["nosniff"]
    assert get_resp_header(conn, "x-frame-options") == ["DENY"]

    [csp] = get_resp_header(conn, "content-security-policy")
    assert csp =~ "frame-ancestors 'none'"
    assert csp =~ "default-src 'self'"
    assert csp =~ "object-src 'none'"

    [referrer] = get_resp_header(conn, "referrer-policy")
    assert referrer == "strict-origin-when-cross-origin"

    [permissions] = get_resp_header(conn, "permissions-policy")
    assert permissions =~ "camera=()"
  end

  test "headers are present on error responses too", %{conn: conn} do
    tenant = insert(:tenant)

    conn =
      conn
      |> with_host(tenant.slug)
      |> get("/api/does-not-exist")

    assert get_resp_header(conn, "x-content-type-options") == ["nosniff"]
    assert get_resp_header(conn, "x-frame-options") == ["DENY"]
  end
end
