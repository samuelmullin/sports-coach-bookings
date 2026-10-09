defmodule SportsCoachBookingsWeb.Staff.CreditsControllerTest do
  use SportsCoachBookingsWeb.ConnCase, async: false

  setup do
    tenant = insert(:tenant)
    SportsCoachBookings.DataCase.put_tenant(tenant)
    %{tenant: tenant}
  end

  defp json_post(conn, path, payload) do
    conn
    |> put_req_header("content-type", "application/json")
    |> post(path, Jason.encode!(payload))
  end

  test "an owner grants, reads, and adjusts a household's credits", %{conn: conn, tenant: tenant} do
    conn = staff_conn(conn, tenant, :owner)
    household = insert(:household).id
    base = "/api/staff/households/#{household}/credits"

    lot =
      conn
      |> json_post("#{base}/grant", %{"amount" => 5, "note" => "welcome"})
      |> json_response(201)

    assert lot["remaining"] == 5
    assert lot["source"] == "admin_grant"

    balance = conn |> get(base) |> json_response(200)
    assert [%{"offering_id" => "any", "amount" => 5}] = balance["data"]

    ledger = conn |> get("#{base}/ledger") |> json_response(200)
    assert [%{"reason" => "grant", "delta" => 5}] = ledger["data"]

    adjusted =
      conn
      |> json_post("#{base}/adjust", %{"lot_id" => lot["id"], "delta" => -2})
      |> json_response(201)

    assert adjusted["remaining"] == 3

    lots = conn |> get("#{base}/lots") |> json_response(200)
    assert [%{"id" => id, "remaining" => 3}] = lots["data"]
    assert id == lot["id"]
  end

  test "a coach may read but cannot grant", %{conn: conn, tenant: tenant} do
    conn = staff_conn(conn, tenant, :coach)
    household = insert(:household).id
    base = "/api/staff/households/#{household}/credits"

    assert %{"data" => []} = conn |> get(base) |> json_response(200)

    assert conn
           |> json_post("#{base}/grant", %{"amount" => 5})
           |> json_response(403)
  end

  test "an anonymous caller is forbidden", %{conn: conn, tenant: tenant} do
    household = insert(:household).id

    resp = conn |> with_host(tenant.slug) |> get("/api/staff/households/#{household}/credits")
    assert json_response(resp, 403)["error"]["code"] == "forbidden"
  end

  test "a negative grant amount is rejected", %{conn: conn, tenant: tenant} do
    conn = staff_conn(conn, tenant, :owner)
    household = insert(:household).id

    resp =
      conn
      |> json_post("/api/staff/households/#{household}/credits/grant", %{"amount" => 0})
      |> json_response(422)

    assert resp["error"]["code"] == "invalid_amount"
  end
end
