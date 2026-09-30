defmodule SportsCoachBookingsWeb.Staff.PaymentsControllerTest do
  use SportsCoachBookingsWeb.ConnCase, async: false

  alias SportsCoachBookings.DataCase
  alias SportsCoachBookings.Payments.ProviderAccount
  alias SportsCoachBookings.Repo

  setup do
    tenant = insert(:tenant, slug: "pay-co")
    DataCase.put_tenant(tenant)
    %{tenant: tenant}
  end

  test "the owner sees the connection status", %{conn: conn, tenant: tenant} do
    conn = staff_conn(conn, tenant, :owner)

    assert %{"status" => "not_connected", "charges_enabled" => false} =
             json_response(get(conn, ~p"/api/staff/payments/connect"), 200)
  end

  test "the owner starts onboarding and gets a hosted URL", %{conn: conn, tenant: tenant} do
    conn = staff_conn(conn, tenant, :owner)

    response = post(conn, ~p"/api/staff/payments/connect/onboarding", %{})

    assert %{"url" => url} = json_response(response, 200)
    assert url =~ "provider.fake/onboarding/"
    assert Repo.get_by(ProviderAccount, tenant_id: tenant.id)
  end

  test "admin and coach are forbidden", %{conn: conn, tenant: tenant} do
    for role <- [:admin, :coach] do
      response = get(staff_conn(conn, tenant, role), ~p"/api/staff/payments/connect")
      assert json_response(response, 403)["error"]["code"] == "forbidden"
    end
  end
end
