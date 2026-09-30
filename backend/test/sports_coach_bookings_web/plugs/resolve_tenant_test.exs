defmodule SportsCoachBookingsWeb.Plugs.ResolveTenantTest do
  use SportsCoachBookingsWeb.ConnCase, async: true

  test "resolves the tenant from the subdomain", %{conn: conn} do
    insert(:tenant, slug: "acme")

    conn = get(with_host(conn, "acme"), "/api/portal/ping")

    assert json_response(conn, 200)["tenant"] == "acme"
    assert json_response(conn, 200)["platform"] == false
  end

  test "returns 404 for an unknown tenant host", %{conn: conn} do
    conn = get(with_host(conn, "does-not-exist"), "/api/portal/ping")

    assert json_response(conn, 404)["error"]["code"] == "tenant_not_found"
  end

  test "treats the bare base domain as the platform host", %{conn: conn} do
    conn = get(%{conn | host: "localhost"}, "/api/portal/ping")

    assert json_response(conn, 200)["platform"] == true
  end
end
