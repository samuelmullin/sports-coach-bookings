defmodule SportsCoachBookingsWeb.Staff.CoachControllerTest do
  use SportsCoachBookingsWeb.ConnCase, async: false

  alias SportsCoachBookings.Bookings.CoachAccess
  alias SportsCoachBookings.Core.StaffActor
  alias SportsCoachBookings.Players
  alias SportsCoachBookings.Staff

  setup do
    CoachAccess.reset_cache()
    tenant = insert(:tenant, slug: "staff-coach-#{System.unique_integer([:positive])}")
    SportsCoachBookings.DataCase.put_tenant(tenant)
    venue = insert(:venue)
    %{tenant: tenant, venue: venue}
  end

  test "a coach sees only their assigned sessions", %{
    conn: conn,
    tenant: tenant,
    venue: venue
  } do
    membership = coach(tenant)
    offering = insert(:offering)
    starts_at = future(3)
    mine = session(venue, offering, starts_at)
    insert(:session_coach, session: mine, membership_id: membership.id)
    _theirs = session(venue, offering, future(4))

    body =
      conn
      |> coach_conn(tenant, membership)
      |> get("/api/staff/coach/sessions")
      |> json_response(200)

    assert [%{"session" => %{"id" => id}}] = body["data"]
    assert id == mine.id
  end

  test "the roster is visible to the assigned coach and 403 to another coach", %{
    conn: conn,
    tenant: tenant,
    venue: venue
  } do
    membership = coach(tenant)
    other = coach(tenant)
    offering = insert(:offering)
    s = session(venue, offering, future(3))
    insert(:session_coach, session: s, membership_id: membership.id)
    player = create_player()
    insert(:booking, session_id: s.id, player_id: player.id, household_id: player.household_id)

    roster =
      conn
      |> coach_conn(tenant, membership)
      |> get("/api/staff/coach/sessions/#{s.id}/roster")
      |> json_response(200)

    assert [%{"player_id" => player_id, "status" => "confirmed"}] = roster["data"]
    assert player_id == player.id

    denied =
      conn
      |> coach_conn(tenant, other)
      |> get("/api/staff/coach/sessions/#{s.id}/roster")
      |> json_response(403)

    assert denied["error"]["code"] == "forbidden"
  end

  test "a coach reads a visible player but not a stranger", %{
    conn: conn,
    tenant: tenant,
    venue: venue
  } do
    membership = coach(tenant)
    offering = insert(:offering)
    s = session(venue, offering, future(3))
    insert(:session_coach, session: s, membership_id: membership.id)
    player = create_player()
    insert(:booking, session_id: s.id, player_id: player.id, household_id: player.household_id)

    visible =
      conn
      |> coach_conn(tenant, membership)
      |> get("/api/staff/coach/players/#{player.id}")
      |> json_response(200)

    assert visible["player"]["id"] == player.id

    stranger = create_player()

    denied =
      conn
      |> coach_conn(tenant, membership)
      |> get("/api/staff/coach/players/#{stranger.id}")
      |> json_response(403)

    assert denied["error"]["code"] == "forbidden"
  end

  test "bulk attendance delegates to Bookings and respects the window", %{
    conn: conn,
    tenant: tenant,
    venue: venue
  } do
    membership = coach(tenant)
    offering = insert(:offering)
    conn = coach_conn(conn, tenant, membership)

    started = session(venue, offering, DateTime.add(DateTime.utc_now(), -3600, :second))
    insert(:session_coach, session: started, membership_id: membership.id)
    player = create_player()

    booking =
      insert(:booking,
        session_id: started.id,
        player_id: player.id,
        household_id: player.household_id
      )

    body =
      conn
      |> json_post("/api/staff/coach/sessions/#{started.id}/attendance", %{
        "attendance" => [%{"booking_id" => booking.id, "status" => "attended"}]
      })
      |> json_response(200)

    assert [%{"ok" => true, "status" => "attended"}] = body["data"]

    upcoming = session(venue, offering, future(3))
    insert(:session_coach, session: upcoming, membership_id: membership.id)
    player2 = create_player()

    booking2 =
      insert(:booking,
        session_id: upcoming.id,
        player_id: player2.id,
        household_id: player2.household_id
      )

    early =
      conn
      |> json_post("/api/staff/coach/sessions/#{upcoming.id}/attendance", %{
        "attendance" => [%{"booking_id" => booking2.id, "status" => "attended"}]
      })
      |> json_response(200)

    assert [%{"ok" => false, "error" => "too_early"}] = early["data"]
  end

  ## Helpers

  defp coach(tenant) do
    email = "coach-#{System.unique_integer([:positive])}@example.com"
    {:ok, staff_user} = Staff.register_staff_user(%{email: email, password: "password1234"})
    {:ok, membership} = Staff.upsert_membership(tenant.id, staff_user.id, :coach)
    membership
  end

  defp coach_conn(conn, tenant, membership) do
    actor =
      StaffActor.new(
        staff_user_id: membership.staff_user_id,
        membership: membership,
        tenant_id: tenant.id,
        role: :coach
      )

    conn
    |> with_host(tenant.slug)
    |> Plug.Conn.assign(:current_staff_actor, actor)
    |> Plug.Conn.assign(:tenant, tenant)
  end

  defp session(venue, offering, starts_at) do
    insert(:session,
      offering_id: offering.id,
      venue_id: venue.id,
      capacity: 5,
      starts_at: starts_at,
      ends_at: DateTime.add(starts_at, 3600, :second)
    )
  end

  defp future(days) do
    DateTime.utc_now()
    |> DateTime.add(days * 86_400, :second)
    |> DateTime.truncate(:microsecond)
  end

  defp create_player do
    {:ok, player} =
      Players.create_player(nil, %{
        household_id: insert(:household).id,
        first_name: "Test",
        last_name: "Player #{System.unique_integer([:positive])}",
        date_of_birth: ~D[2015-05-01]
      })

    player
  end

  defp json_post(conn, path, payload) do
    conn
    |> put_req_header("content-type", "application/json")
    |> post(path, Jason.encode!(payload))
  end
end
