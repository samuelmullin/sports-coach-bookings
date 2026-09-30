defmodule SportsCoachBookingsWeb.StaffNotificationsControllerTest do
  use SportsCoachBookingsWeb.ConnCase, async: false

  alias SportsCoachBookings.DataCase
  alias SportsCoachBookings.Notifications
  alias SportsCoachBookings.Notifications.Delivery
  alias SportsCoachBookings.Repo

  @assigns %{name: "Alex", action_url: "https://example.com"}

  setup do
    tenant = insert(:tenant, slug: "acme")
    DataCase.put_tenant(tenant)

    {:ok, %{deliveries: [delivery]}} =
      Notifications.deliver(
        :sample,
        [%{type: :email, email: "log@example.com"}],
        @assigns
      )

    %{tenant: tenant, delivery: delivery}
  end

  test "owner views the delivery log for an email", %{conn: conn, tenant: tenant} do
    conn = staff_conn(conn, tenant, :owner)

    response = get(conn, "/api/staff/notifications/deliveries?email=log@example.com")
    body = json_response(response, 200)

    assert [row] = body["data"]
    assert row["email"] == "log@example.com"
    assert row["template_key"] == "sample"
    assert row["status"] == "queued"
  end

  test "owner views the delivery log for a customer", %{conn: conn, tenant: tenant} do
    customer = insert(:customer_user, tenant_id: tenant.id, email: "log@example.com")
    conn = staff_conn(conn, tenant, :owner)

    response = get(conn, "/api/staff/notifications/deliveries?customer_id=#{customer.id}")
    assert json_response(response, 200)["data"] != []
  end

  test "resends a delivery", %{conn: conn, tenant: tenant, delivery: delivery} do
    conn = staff_conn(conn, tenant, :admin)

    response = post(conn, "/api/staff/notifications/deliveries/#{delivery.id}/resend")
    body = json_response(response, 200)

    assert body["status"] == "queued"
    assert body["id"] != delivery.id
    assert Repo.aggregate(Delivery, :count) == 2
  end

  test "refuses to resend a suppressed address", %{
    conn: conn,
    tenant: tenant,
    delivery: delivery
  } do
    insert(:suppression, tenant_id: tenant.id, email: delivery.email, reason: :complaint)
    conn = staff_conn(conn, tenant, :owner)

    response = post(conn, "/api/staff/notifications/deliveries/#{delivery.id}/resend")
    assert json_response(response, 422)["error"]["code"] == "suppressed"
  end

  test "requires a filter" do
    tenant = insert(:tenant, slug: "filterless")
    DataCase.put_tenant(tenant)
    conn = staff_conn(build_conn(), tenant, :owner)

    response = get(conn, "/api/staff/notifications/deliveries")
    assert json_response(response, 422)["error"]["code"] == "missing_filter"
  end

  test "anonymous callers are forbidden", %{tenant: tenant} do
    response =
      build_conn()
      |> host(tenant.slug)
      |> get("/api/staff/notifications/deliveries?email=log@example.com")

    assert json_response(response, 403)["error"]["code"] == "forbidden"
  end

  defp host(conn, slug), do: %{conn | host: "#{slug}.localhost"}
end
