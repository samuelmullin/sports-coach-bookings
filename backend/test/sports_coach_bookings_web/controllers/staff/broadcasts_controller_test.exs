defmodule SportsCoachBookingsWeb.Staff.BroadcastsControllerTest do
  use SportsCoachBookingsWeb.ConnCase, async: false

  alias SportsCoachBookings.Notifications
  alias SportsCoachBookings.Notifications.Broadcasts.Broadcast
  alias SportsCoachBookings.Notifications.Broadcasts.BroadcastRecipient
  alias SportsCoachBookings.ObanHelpers
  alias SportsCoachBookings.Repo

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

  defp json_patch(conn, path, payload) do
    conn
    |> put_req_header("content-type", "application/json")
    |> patch(path, Jason.encode!(payload))
  end

  defp manager(tenant, email, marketing_opt_in) do
    household = insert(:household, tenant_id: tenant.id)
    customer = insert(:customer_user, tenant_id: tenant.id, email: email)
    insert(:household_member, tenant_id: tenant.id, household: household, customer_user: customer)

    if marketing_opt_in do
      {:ok, _} =
        Notifications.Preferences.update({:customer_user, customer.id}, %{marketing_opt_in: true})
    end

    %{household: household}
  end

  defp drain_notifications do
    case ObanHelpers.drain(:notifications) do
      0 -> :ok
      _ -> drain_notifications()
    end
  end

  test "owner can create, read, update, schedule, cancel, and delete a broadcast", %{
    conn: conn,
    tenant: tenant
  } do
    conn = staff_conn(conn, tenant, :owner)

    created =
      conn
      |> json_post("/api/staff/broadcasts", %{
        "subject" => "Fall news",
        "body_markdown" => "# Fall\n\n**Registration** is open.",
        "category" => "marketing"
      })
      |> json_response(201)

    assert created["status"] == "draft"
    assert created["subject"] == "Fall news"

    id = created["id"]

    assert %{"id" => ^id, "status" => "draft"} =
             conn |> get("/api/staff/broadcasts/#{id}") |> json_response(200)

    updated =
      conn
      |> json_patch("/api/staff/broadcasts/#{id}", %{"subject" => "Fall news v2"})
      |> json_response(200)

    assert updated["subject"] == "Fall news v2"

    preview = conn |> post("/api/staff/broadcasts/#{id}/preview") |> json_response(200)
    assert preview["recipient_count"] == 0
    assert preview["html"] =~ "<h1>Fall</h1>"

    counts = conn |> get("/api/staff/broadcasts/#{id}/recipients") |> json_response(200)
    assert counts["recipient_count"] == 0

    future = DateTime.add(DateTime.utc_now(), 3600, :second) |> DateTime.to_iso8601()

    scheduled =
      conn
      |> json_post("/api/staff/broadcasts/#{id}/schedule", %{"scheduled_for" => future})
      |> json_response(200)

    assert scheduled["status"] == "scheduled"

    cancelled = conn |> post("/api/staff/broadcasts/#{id}/cancel") |> json_response(200)
    assert cancelled["status"] == "cancelled"

    draft =
      conn
      |> json_post("/api/staff/broadcasts", %{
        "subject" => "Throwaway",
        "body_markdown" => "Throwaway",
        "category" => "marketing"
      })
      |> json_response(201)

    assert conn |> delete("/api/staff/broadcasts/#{draft["id"]}") |> response(204)
  end

  test "index lists broadcasts", %{conn: conn, tenant: tenant} do
    conn = staff_conn(conn, tenant, :owner)

    broadcast =
      insert(:broadcast, tenant_id: tenant.id, subject: "Listed")

    body = conn |> get("/api/staff/broadcasts") |> json_response(200)
    assert Enum.any?(body["data"], &(&1["id"] == broadcast.id))
  end

  test "send + history reflects recipients", %{conn: conn, tenant: tenant} do
    conn = staff_conn(conn, tenant, :owner)
    h = manager(tenant, "segment@example.com", true)

    offering = insert(:offering, tenant_id: tenant.id)
    session = insert(:session, tenant_id: tenant.id, offering_id: offering.id, status: :scheduled)
    player = insert(:player, tenant_id: tenant.id, household_id: h.household.id)

    insert(:booking,
      tenant_id: tenant.id,
      session_id: session.id,
      player_id: player.id,
      household_id: h.household.id,
      status: :confirmed
    )

    created =
      conn
      |> json_post("/api/staff/broadcasts", %{
        "subject" => "Session news",
        "body_markdown" => "Hello",
        "category" => "marketing",
        "segment" => %{
          "match" => "all",
          "conditions" => [%{"type" => "bookings", "session_ids" => [session.id]}]
        }
      })
      |> json_response(201)

    sent = conn |> post("/api/staff/broadcasts/#{created["id"]}/send") |> json_response(200)
    assert sent["status"] == "sending"

    drain_notifications()

    assert Repo.get!(Broadcast, created["id"]).status == :sent
    assert Repo.aggregate(BroadcastRecipient, :count) == 1

    history = conn |> get("/api/staff/broadcasts/#{created["id"]}/history") |> json_response(200)
    assert history["stats"]["total"] == 1
    assert [%{"email" => "segment@example.com"}] = history["data"]
  end

  test "send test to an address", %{conn: conn, tenant: tenant} do
    conn = staff_conn(conn, tenant, :owner)

    created =
      conn
      |> json_post("/api/staff/broadcasts", %{
        "subject" => "Test",
        "body_markdown" => "Test",
        "category" => "marketing"
      })
      |> json_response(201)

    body =
      conn
      |> json_post("/api/staff/broadcasts/#{created["id"]}/test", %{"email" => "me@example.com"})
      |> json_response(200)

    assert body["email"] == "me@example.com"
  end

  test "operational broadcast without a booking segment is rejected", %{
    conn: conn,
    tenant: tenant
  } do
    conn = staff_conn(conn, tenant, :owner)

    response =
      conn
      |> json_post("/api/staff/broadcasts", %{
        "subject" => "Ops",
        "body_markdown" => "Ops",
        "category" => "operational"
      })
      |> json_response(422)

    assert response["error"]["code"] == "validation_error"
    assert response["error"]["details"]["fields"]["segment"]
  end

  test "a coach is forbidden", %{conn: conn, tenant: tenant} do
    conn = staff_conn(conn, tenant, :coach)

    assert conn |> get("/api/staff/broadcasts") |> json_response(403)
  end

  test "an anonymous caller is forbidden", %{conn: conn, tenant: tenant} do
    resp = conn |> with_host(tenant.slug) |> get("/api/staff/broadcasts")
    assert json_response(resp, 403)["error"]["code"] == "forbidden"
  end
end
