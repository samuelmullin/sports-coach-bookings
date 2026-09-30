defmodule SportsCoachBookingsWeb.Portal.PoliciesControllerTest do
  use SportsCoachBookingsWeb.ConnCase, async: false

  alias SportsCoachBookings.Policies
  alias SportsCoachBookings.Policies.Rules

  setup do
    tenant = insert(:tenant)
    SportsCoachBookings.DataCase.put_tenant(tenant)
    %{tenant: tenant}
  end

  test "returns the default policy summary for an offering", %{conn: conn, tenant: tenant} do
    offering = insert(:offering, tenant_id: tenant.id)

    {:ok, policy} =
      Policies.create_policy(nil, %{
        "name" => "Standard",
        "rules" => Rules.default_map(),
        "customer_facing_summary" => "Cancel 24 hours ahead."
      })

    response = get(customer_conn(conn, tenant), "/api/portal/policies/offerings/#{offering.id}")
    body = json_response(response, 200)

    assert body["policy_id"] == policy.id
    assert body["policy_name"] == "Standard"
    assert body["summary"] == "Cancel 24 hours ahead."
  end

  test "an anonymous caller may read the summary", %{conn: conn, tenant: tenant} do
    offering = insert(:offering, tenant_id: tenant.id)

    response = get(with_host(conn, tenant.slug), "/api/portal/policies/offerings/#{offering.id}")
    assert json_response(response, 200)["offering_id"] == offering.id
  end

  test "returns 404 for an unknown offering", %{conn: conn, tenant: tenant} do
    response =
      get(
        customer_conn(conn, tenant),
        "/api/portal/policies/offerings/#{Ecto.UUID.generate()}"
      )

    assert json_response(response, 404)["error"]["code"] == "not_found"
  end
end
