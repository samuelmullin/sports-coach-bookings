defmodule SportsCoachBookings.Security.AuthorizationMatrixTest do
  @moduledoc """
  WP-19 authorization sweep at the controller boundary: every actor kind is
  denied unless the owning policy allows it. Policy unit tests cover the full
  action matrix per context; these tests assert the controllers actually call
  the policy and that the plugs enforce role/membership.
  """

  use SportsCoachBookingsWeb.ConnCase, async: true

  setup do
    %{tenant: insert(:tenant)}
  end

  test "anonymous staff request is rejected", %{conn: conn, tenant: tenant} do
    assert conn
           |> with_host(tenant.slug)
           |> get(~p"/api/staff/players")
           |> response(403)
  end

  test "a customer cannot use staff routes", %{conn: conn, tenant: tenant} do
    assert conn
           |> customer_conn(tenant)
           |> get(~p"/api/staff/players")
           |> response(403)
  end

  test "a coach cannot update tenant settings (admin-only)", %{conn: conn, tenant: tenant} do
    assert conn
           |> staff_conn(tenant, :coach)
           |> patch(~p"/api/staff/settings", %{settings: %{name: "Hacked"}})
           |> response(403)
  end

  test "a coach cannot read tenant settings (admin-only)", %{conn: conn, tenant: tenant} do
    assert conn
           |> staff_conn(tenant, :coach)
           |> get(~p"/api/staff/settings")
           |> response(403)
  end

  test "an admin cannot delete the tenant (owner-only)", %{conn: conn, tenant: tenant} do
    assert conn
           |> staff_conn(tenant, :admin)
           |> delete(~p"/api/staff/settings")
           |> response(403)
  end

  test "an owner can read tenant settings", %{conn: conn, tenant: tenant} do
    assert conn
           |> staff_conn(tenant, :owner)
           |> get(~p"/api/staff/settings")
           |> response(200)
  end
end
