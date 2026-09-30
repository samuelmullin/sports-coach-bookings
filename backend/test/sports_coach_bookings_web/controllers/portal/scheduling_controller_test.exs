defmodule SportsCoachBookingsWeb.Portal.ScheduleControllerTest do
  use SportsCoachBookingsWeb.ConnCase, async: false

  setup do
    tenant = insert(:tenant)
    SportsCoachBookings.DataCase.put_tenant(tenant)

    offering = insert(:offering, tenant_id: tenant.id, duration_minutes: 60, default_capacity: 6)
    venue = insert(:venue, tenant_id: tenant.id, timezone: "America/Halifax")

    %{tenant: tenant, offering: offering, venue: venue}
  end

  defp upcoming_session(tenant, offering, venue, attrs \\ %{}) do
    starts_at =
      DateTime.utc_now()
      |> DateTime.add(3, :day)
      |> DateTime.truncate(:microsecond)

    base = %{
      tenant_id: tenant.id,
      offering_id: offering.id,
      venue_id: venue.id,
      starts_at: starts_at,
      ends_at: DateTime.add(starts_at, 3600, :second),
      capacity: 6
    }

    insert(:session, Map.merge(base, Map.new(attrs)))
  end

  test "anyone can list upcoming bookable sessions", %{
    conn: conn,
    tenant: tenant,
    offering: offering,
    venue: venue
  } do
    session = upcoming_session(tenant, offering, venue)

    body =
      conn
      |> with_host(tenant.slug)
      |> get("/api/portal/sessions")
      |> json_response(200)

    entry = Enum.find(body["data"], &(&1["session"]["id"] == session.id))
    assert entry["bookable"] == true
    assert entry["not_bookable_reason"] == nil
    assert entry["offering"]["id"] == offering.id
    assert entry["venue"]["id"] == venue.id
  end

  test "hidden sessions are not listed", %{
    conn: conn,
    tenant: tenant,
    offering: offering,
    venue: venue
  } do
    upcoming_session(tenant, offering, venue, visibility: :hidden)

    body =
      conn
      |> with_host(tenant.slug)
      |> get("/api/portal/sessions")
      |> json_response(200)

    assert body["data"] == []
  end

  test "cancelled sessions are not listed", %{
    conn: conn,
    tenant: tenant,
    offering: offering,
    venue: venue
  } do
    upcoming_session(tenant, offering, venue, status: :cancelled)

    body =
      conn
      |> with_host(tenant.slug)
      |> get("/api/portal/sessions")
      |> json_response(200)

    assert body["data"] == []
  end

  test "a range over 62 days is rejected", %{conn: conn, tenant: tenant} do
    body =
      conn
      |> with_host(tenant.slug)
      |> get("/api/portal/sessions?from=2026-01-01T00:00:00Z&to=2026-06-01T00:00:00Z")
      |> json_response(422)

    assert body["error"]["code"] == "range_too_large"
  end

  describe "show" do
    test "anyone can fetch a public session detail", %{
      conn: conn,
      tenant: tenant,
      offering: offering,
      venue: venue
    } do
      session = upcoming_session(tenant, offering, venue)

      body =
        conn
        |> with_host(tenant.slug)
        |> get("/api/portal/sessions/#{session.id}")
        |> json_response(200)

      assert body["session"]["id"] == session.id
      assert body["offering"]["id"] == offering.id
      assert body["venue"]["id"] == venue.id
      assert body["bookable"] == true
    end

    test "hidden sessions are not found", %{
      conn: conn,
      tenant: tenant,
      offering: offering,
      venue: venue
    } do
      session = upcoming_session(tenant, offering, venue, visibility: :hidden)

      conn
      |> with_host(tenant.slug)
      |> get("/api/portal/sessions/#{session.id}")
      |> json_response(404)
    end

    test "cancelled sessions are not found", %{
      conn: conn,
      tenant: tenant,
      offering: offering,
      venue: venue
    } do
      session = upcoming_session(tenant, offering, venue, status: :cancelled)

      conn
      |> with_host(tenant.slug)
      |> get("/api/portal/sessions/#{session.id}")
      |> json_response(404)
    end

    test "a missing session is not found", %{conn: conn, tenant: tenant} do
      conn
      |> with_host(tenant.slug)
      |> get("/api/portal/sessions/#{Ecto.UUID.generate()}")
      |> json_response(404)
    end
  end
end
