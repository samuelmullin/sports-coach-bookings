defmodule SportsCoachBookingsWeb.Staff.ScheduleControllerTest do
  use SportsCoachBookingsWeb.ConnCase, async: false

  alias SportsCoachBookings.Core.StaffActor

  setup do
    tenant = insert(:tenant)
    SportsCoachBookings.DataCase.put_tenant(tenant)

    offering = insert(:offering, tenant_id: tenant.id, duration_minutes: 60, default_capacity: 6)
    venue = insert(:venue, tenant_id: tenant.id, timezone: "America/Halifax")
    coach = insert(:membership, tenant_id: tenant.id, role: :coach)

    %{tenant: tenant, offering: offering, venue: venue, coach: coach}
  end

  defp json_post(conn, path, payload) do
    conn
    |> put_req_header("content-type", "application/json")
    |> post(path, Jason.encode!(payload))
  end

  defp future(days) do
    DateTime.utc_now() |> DateTime.add(days, :day) |> DateTime.to_iso8601()
  end

  describe "sessions" do
    test "an owner creates a session", %{
      conn: conn,
      tenant: tenant,
      offering: offering,
      venue: venue
    } do
      conn = staff_conn(conn, tenant, :owner)

      resp =
        json_post(conn, "/api/staff/schedule/sessions", %{
          "offering_id" => offering.id,
          "venue_id" => venue.id,
          "starts_at" => future(3)
        })

      body = json_response(resp, 201)
      assert body["session"]["capacity"] == 6
      assert body["session"]["status"] == "scheduled"
      assert body["warnings"] == []
    end

    test "a coach cannot create a session", %{
      conn: conn,
      tenant: tenant,
      offering: offering,
      venue: venue
    } do
      conn = staff_conn(conn, tenant, :coach)

      resp =
        json_post(conn, "/api/staff/schedule/sessions", %{
          "offering_id" => offering.id,
          "venue_id" => venue.id,
          "starts_at" => future(3)
        })

      assert json_response(resp, 403)["error"]["code"] == "forbidden"
    end

    test "the staff calendar includes hidden sessions and warnings", %{
      conn: conn,
      tenant: tenant,
      offering: offering,
      venue: venue,
      coach: coach
    } do
      conn = staff_conn(conn, tenant, :owner)

      json_post(conn, "/api/staff/schedule/sessions", %{
        "offering_id" => offering.id,
        "venue_id" => venue.id,
        "starts_at" => future(3),
        "visibility" => "hidden",
        "coach_ids" => [coach.id]
      })

      json_post(conn, "/api/staff/schedule/sessions", %{
        "offering_id" => offering.id,
        "venue_id" => venue.id,
        "starts_at" => future(3),
        "coach_ids" => [coach.id]
      })

      resp = get(conn, "/api/staff/schedule/sessions")
      body = json_response(resp, 200)

      assert length(body["data"]) == 2

      assert Enum.any?(body["data"], fn entry ->
               Enum.any?(entry["warnings"], &(&1["type"] == "coach_double_booked"))
             end)
    end

    test "session detail includes an empty roster when Bookings is absent", %{
      conn: conn,
      tenant: tenant,
      offering: offering,
      venue: venue
    } do
      conn = staff_conn(conn, tenant, :owner)

      created =
        json_post(conn, "/api/staff/schedule/sessions", %{
          "offering_id" => offering.id,
          "venue_id" => venue.id,
          "starts_at" => future(3)
        })

      id = json_response(created, 201)["session"]["id"]

      body = json_response(get(conn, "/api/staff/schedule/sessions/#{id}"), 200)
      assert body["roster"] == []
      assert body["session"]["id"] == id
    end

    test "an owner cancels a session and gets the impact", %{
      conn: conn,
      tenant: tenant,
      offering: offering,
      venue: venue
    } do
      conn = staff_conn(conn, tenant, :owner)

      created =
        json_post(conn, "/api/staff/schedule/sessions", %{
          "offering_id" => offering.id,
          "venue_id" => venue.id,
          "starts_at" => future(3)
        })

      id = json_response(created, 201)["session"]["id"]

      resp = json_post(conn, "/api/staff/schedule/sessions/#{id}/cancel", %{"reason" => "snow"})
      body = json_response(resp, 200)
      assert body["session"]["status"] == "cancelled"
      assert body["session"]["cancel_reason"] == "snow"
      assert body["impact"] == %{"booked_count" => 0, "held_count" => 0}
    end
  end

  describe "series" do
    test "an owner creates a series", %{
      conn: conn,
      tenant: tenant,
      offering: offering,
      venue: venue,
      coach: coach
    } do
      conn = staff_conn(conn, tenant, :owner)

      resp =
        json_post(conn, "/api/staff/schedule/series", %{
          "offering_id" => offering.id,
          "venue_id" => venue.id,
          "weekdays" => [2],
          "start_time_local" => "17:00",
          "duration_minutes" => 60,
          "starts_on" => "2026-11-01",
          "ends_on" => "2026-11-30",
          "coach_ids" => [coach.id]
        })

      body = json_response(resp, 201)
      assert body["series"]["weekdays"] == [2]
      assert length(body["sessions"]) == 4
    end

    test "edit_series requires confirmation for booked occurrences", %{
      conn: conn,
      tenant: tenant,
      offering: offering,
      venue: venue
    } do
      conn = staff_conn(conn, tenant, :owner)

      created =
        json_post(conn, "/api/staff/schedule/series", %{
          "offering_id" => offering.id,
          "venue_id" => venue.id,
          "weekdays" => [2],
          "start_time_local" => "17:00",
          "duration_minutes" => 60,
          "starts_on" => "2026-11-01",
          "ends_on" => "2026-11-30"
        })

      %{"sessions" => [first | _]} = json_response(created, 201)

      resp =
        json_post(conn, "/api/staff/schedule/sessions/#{first["id"]}/edit_series", %{
          "scope" => "following",
          "start_time_local" => "18:00"
        })

      assert json_response(resp, 200)["sessions"] |> length() == 4
    end
  end

  describe "my_sessions" do
    test "a coach sees their own sessions", %{
      conn: conn,
      tenant: tenant,
      offering: offering,
      venue: venue
    } do
      staff_user = insert(:staff_user)

      membership =
        insert(:membership,
          tenant_id: tenant.id,
          role: :coach,
          staff_user: staff_user,
          staff_user_id: staff_user.id
        )

      owner = staff_conn(conn, tenant, :owner)

      json_post(owner, "/api/staff/schedule/sessions", %{
        "offering_id" => offering.id,
        "venue_id" => venue.id,
        "starts_at" => future(3),
        "coach_ids" => [membership.id]
      })

      actor =
        StaffActor.new(
          staff_user_id: staff_user.id,
          membership: membership,
          tenant_id: tenant.id,
          role: :coach
        )

      coach_conn =
        conn
        |> with_host(tenant.slug)
        |> Plug.Conn.assign(:current_staff_actor, actor)
        |> Plug.Conn.assign(:tenant, tenant)

      body = json_response(get(coach_conn, "/api/staff/my-sessions"), 200)
      assert length(body["data"]) == 1
    end
  end
end
