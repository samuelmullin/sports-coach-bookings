defmodule SportsCoachBookingsWeb.Staff.PoliciesControllerTest do
  use SportsCoachBookingsWeb.ConnCase, async: false

  alias SportsCoachBookings.Policies
  alias SportsCoachBookings.Policies.Rules
  alias SportsCoachBookings.Repo

  setup do
    tenant = insert(:tenant)
    SportsCoachBookings.DataCase.put_tenant(tenant)
    %{tenant: tenant}
  end

  defp json(conn, method, path, payload) do
    conn
    |> put_req_header("content-type", "application/json")
    |> method.(path, Jason.encode!(payload))
  end

  defp rules, do: Rules.default_map()

  defp create_policy!(conn, name, opts \\ %{}) do
    payload = Map.merge(%{"name" => name, "rules" => rules()}, opts)

    conn
    |> json(&post/3, "/api/staff/policies", payload)
    |> json_response(201)
  end

  test "an owner creates, lists, shows and updates a policy", %{conn: conn, tenant: tenant} do
    conn = staff_conn(conn, tenant, :owner)
    created = create_policy!(conn, "Standard")
    assert created["is_default"]
    assert created["version"] == 1
    assert length(created["rules"]["cancellation_tiers"]) == 2

    listed = json_response(get(conn, "/api/staff/policies"), 200)
    assert [%{"id" => id}] = listed["data"]
    assert id == created["id"]

    filtered = json_response(get(conn, "/api/staff/policies?is_default=true"), 200)
    assert [%{"id" => ^id}] = filtered["data"]

    shown = json_response(get(conn, "/api/staff/policies/#{id}"), 200)
    assert shown["name"] == "Standard"

    updated =
      conn
      |> json(&patch/3, "/api/staff/policies/#{id}", %{
        "name" => "Standard v2",
        "rules" => rules()
      })
      |> json_response(200)

    assert updated["version"] == 2
  end

  test "an owner can set a default and assign offerings", %{conn: conn, tenant: tenant} do
    conn = staff_conn(conn, tenant, :owner)
    first = create_policy!(conn, "First")
    second = create_policy!(conn, "Second")
    offering = insert(:offering, tenant_id: tenant.id)

    promoted =
      conn
      |> post("/api/staff/policies/#{second["id"]}/default", %{})
      |> json_response(200)

    assert promoted["is_default"]

    assert Repo.get!(SportsCoachBookings.Policies.CancellationPolicy, first["id"]).is_default ==
             false

    assigned =
      conn
      |> json(&post/3, "/api/staff/policies/#{second["id"]}/assign", %{
        "offering_ids" => [offering.id]
      })
      |> json_response(200)

    assert [%{"offering_id" => offering_id}] = assigned["data"]
    assert offering_id == offering.id

    removed =
      conn
      |> delete("/api/staff/policies/assignments/#{offering.id}")
      |> json_response(200)

    assert removed["removed"] == 1
  end

  test "the simulator returns an outcome", %{conn: conn, tenant: tenant} do
    conn = staff_conn(conn, tenant, :owner)
    create_policy!(conn, "Standard")

    early =
      conn
      |> json(&post/3, "/api/staff/policies/simulate", %{
        "action" => "cancel",
        "hours_before" => 30
      })
      |> json_response(200)

    assert early["outcome"]["credit_outcome"] == "return"

    late =
      conn
      |> json(&post/3, "/api/staff/policies/simulate", %{
        "action" => "cancel",
        "hours_before" => 1
      })
      |> json_response(200)

    assert late["outcome"]["credit_outcome"] == "forfeit"
  end

  test "a coach can read but not write", %{conn: conn, tenant: tenant} do
    staff_conn(conn, tenant, :owner) |> create_policy!("Standard")
    coach = staff_conn(conn, tenant, :coach)

    assert json_response(get(coach, "/api/staff/policies"), 200)["data"] != []

    forbidden =
      coach
      |> json(&post/3, "/api/staff/policies", %{"name" => "Nope", "rules" => rules()})
      |> json_response(403)

    assert forbidden["error"]["code"] == "forbidden"
  end

  test "an anonymous caller is denied", %{conn: conn, tenant: tenant} do
    response = get(with_host(conn, tenant.slug), "/api/staff/policies")
    assert json_response(response, 403)["error"]["code"] == "forbidden"
  end

  test "invalid rules return 422", %{conn: conn, tenant: tenant} do
    conn = staff_conn(conn, tenant, :owner)

    bad_rules = Map.put(rules(), "cancellation_tiers", [])

    response =
      conn
      |> json(&post/3, "/api/staff/policies", %{"name" => "Bad", "rules" => bad_rules})
      |> json_response(422)

    assert response["error"]["code"] == "validation_error"
  end

  test "the created default policy is what snapshot_for resolves", %{conn: conn, tenant: tenant} do
    conn = staff_conn(conn, tenant, :owner)
    policy = create_policy!(conn, "Standard")
    offering = insert(:offering, tenant_id: tenant.id)

    assert Policies.snapshot_for(offering.id)["policy_id"] == policy["id"]
  end
end
