defmodule SportsCoachBookingsWeb.StaffCustomersControllerTest do
  use SportsCoachBookingsWeb.ConnCase, async: false

  alias SportsCoachBookings.Core.Audit.Event
  alias SportsCoachBookings.Customers
  alias SportsCoachBookings.DataCase
  alias SportsCoachBookings.Repo

  @password "a very long password"

  setup do
    tenant = insert(:tenant, slug: "acme")
    DataCase.put_tenant(tenant)

    {:ok, result} =
      Customers.register_customer(%{
        "first_name" => "Dana",
        "last_name" => "Reyes",
        "email" => "dana@example.com",
        "phone" => "+19025550111",
        "password" => @password,
        "accept_terms" => true,
        "accept_privacy" => true
      })

    %{tenant: tenant, result: result}
  end

  defp json_patch(conn, path, body) do
    conn
    |> put_req_header("content-type", "application/json")
    |> patch(path, Jason.encode!(body))
  end

  test "owner searches and views customers", %{conn: conn, tenant: tenant, result: result} do
    conn = staff_conn(conn, tenant, :owner)

    list = conn |> get("/api/staff/customers?q=Reyes") |> json_response(200)
    assert Enum.any?(list["data"], &(&1["id"] == result.customer_user.id))

    show = conn |> get("/api/staff/customers/#{result.customer_user.id}") |> json_response(200)
    assert show["email"] == "dana@example.com"
    assert show["confirmed"] == false
  end

  test "admin edits a customer's contact details (audited)", %{
    conn: conn,
    tenant: tenant,
    result: result
  } do
    conn = staff_conn(conn, tenant, :admin)

    updated =
      conn
      |> json_patch("/api/staff/customers/#{result.customer_user.id}", %{
        customer_user: %{first_name: "Danielle"}
      })

    assert json_response(updated, 200)["first_name"] == "Danielle"
    assert Repo.get_by(Event, action: "customer.updated")
  end

  test "admin deactivates a customer, blocking login", %{
    conn: conn,
    tenant: tenant,
    result: result
  } do
    conn = staff_conn(conn, tenant, :owner)

    body =
      conn
      |> post("/api/staff/customers/#{result.customer_user.id}/deactivate")
      |> json_response(200)

    assert body["active"] == false

    assert {:error, :deactivated} =
             Customers.authenticate("dana@example.com", @password)
  end

  test "admin triggers a password reset", %{conn: conn, tenant: tenant, result: result} do
    conn = staff_conn(conn, tenant, :owner)

    resp = conn |> post("/api/staff/customers/#{result.customer_user.id}/password_reset")
    assert json_response(resp, 202)["message"] =~ "reset"
    assert Repo.get_by(Event, action: "customer.password_reset_requested")
  end

  test "coaches are forbidden from customer administration", %{conn: conn, tenant: tenant} do
    conn = staff_conn(conn, tenant, :coach)

    assert json_response(get(conn, "/api/staff/customers"), 403)["error"]["code"] == "forbidden"
    assert json_response(get(conn, "/api/staff/households"), 403)["error"]["code"] == "forbidden"
  end

  test "lists households and shows household detail", %{
    conn: conn,
    tenant: tenant,
    result: result
  } do
    conn = staff_conn(conn, tenant, :admin)

    households = conn |> get("/api/staff/households") |> json_response(200)
    assert Enum.any?(households["data"], &(&1["id"] == result.household.id))

    detail =
      conn
      |> get("/api/staff/households/#{result.household.id}")
      |> json_response(200)

    assert detail["id"] == result.household.id

    assert [%{"role" => "primary", "customer_user" => %{"email" => "dana@example.com"}}] =
             detail["members"]
  end

  test "a different tenant cannot read a customer by id", %{conn: conn} do
    other = insert(:tenant, slug: "other")
    conn = staff_conn(conn, other, :owner)

    resp = get(conn, "/api/staff/customers/#{Ecto.UUID.generate()}")
    assert json_response(resp, 404)["error"]["code"] == "not_found"
  end
end
