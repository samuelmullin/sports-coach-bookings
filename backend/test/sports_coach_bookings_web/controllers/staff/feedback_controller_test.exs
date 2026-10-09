defmodule SportsCoachBookingsWeb.Staff.FeedbackControllerTest do
  use SportsCoachBookingsWeb.ConnCase, async: false

  alias SportsCoachBookings.Bookings.CoachAccess
  alias SportsCoachBookings.Core.StaffActor
  alias SportsCoachBookings.ObanHelpers
  alias SportsCoachBookings.Players
  alias SportsCoachBookings.Staff

  setup do
    CoachAccess.reset_cache()
    tenant = insert(:tenant, slug: "staff-feedback-#{System.unique_integer([:positive])}")
    SportsCoachBookings.DataCase.put_tenant(tenant)
    venue = insert(:venue)
    %{tenant: tenant, venue: venue}
  end

  test "a coach creates, shares, and edits feedback for an assigned session", %{
    conn: conn,
    tenant: tenant,
    venue: venue
  } do
    membership = coach(tenant)
    offering = insert(:offering)
    s = assigned_session(venue, offering, membership, -1)
    player = create_player()
    insert(:booking, session_id: s.id, player_id: player.id, household_id: player.household_id)

    created =
      conn
      |> coach_conn(tenant, membership)
      |> json_post("/api/staff/feedback", %{
        "session_id" => s.id,
        "player_id" => player.id,
        "body" => "Great first touch."
      })
      |> json_response(201)

    assert created["visibility"] == "internal"
    assert ObanHelpers.event_count("feedback.submitted") == 0

    shared =
      conn
      |> coach_conn(tenant, membership)
      |> post("/api/staff/feedback/#{created["id"]}/share")
      |> json_response(200)

    assert shared["visibility"] == "shared"
    assert ObanHelpers.event_count("feedback.submitted") == 1

    edited =
      conn
      |> coach_conn(tenant, membership)
      |> json_patch("/api/staff/feedback/#{created["id"]}", %{
        "feedback" => %{"body" => "Updated"}
      })
      |> json_response(200)

    assert edited["body"] == "Updated"
    assert ObanHelpers.event_count("feedback.submitted") == 1
  end

  test "a coach cannot submit feedback for a session they are not assigned to", %{
    conn: conn,
    tenant: tenant,
    venue: venue
  } do
    membership = coach(tenant)
    offering = insert(:offering)
    s = assigned_session(venue, offering, nil, -1)
    player = create_player()
    insert(:booking, session_id: s.id, player_id: player.id, household_id: player.household_id)

    resp =
      conn
      |> coach_conn(tenant, membership)
      |> json_post("/api/staff/feedback", %{
        "session_id" => s.id,
        "player_id" => player.id,
        "body" => "Nope"
      })
      |> json_response(403)

    assert resp["error"]["code"] == "forbidden"
  end

  test "the portal never returns internal feedback", %{
    conn: conn,
    tenant: tenant,
    venue: venue
  } do
    membership = coach(tenant)
    offering = insert(:offering)
    s = assigned_session(venue, offering, membership, -1)
    player = create_player()
    insert(:booking, session_id: s.id, player_id: player.id, household_id: player.household_id)

    coach_conn(conn, tenant, membership)
    |> json_post("/api/staff/feedback", %{
      "session_id" => s.id,
      "player_id" => player.id,
      "body" => "Internal only"
    })
    |> json_response(201)

    assert SportsCoachBookings.Feedback.shared_for_player(player.id) == []
  end

  test "owners/admin review all feedback; a coach only their own", %{
    conn: conn,
    tenant: tenant,
    venue: venue
  } do
    membership = coach(tenant)
    other = coach(tenant)
    offering = insert(:offering)

    s1 = assigned_session(venue, offering, membership, -1)
    player1 = create_player()
    insert(:booking, session_id: s1.id, player_id: player1.id, household_id: player1.household_id)

    {:ok, _} =
      SportsCoachBookings.Feedback.create_feedback(coach_actor(tenant, membership), %{
        session_id: s1.id,
        player_id: player1.id,
        body: "Mine",
        visibility: "shared"
      })

    s2 = assigned_session(venue, offering, other, -1)
    player2 = create_player()
    insert(:booking, session_id: s2.id, player_id: player2.id, household_id: player2.household_id)

    {:ok, _} =
      SportsCoachBookings.Feedback.create_feedback(coach_actor(tenant, other), %{
        session_id: s2.id,
        player_id: player2.id,
        body: "Theirs"
      })

    owner = conn |> staff_conn(tenant, :owner) |> get("/api/staff/feedback") |> json_response(200)
    assert length(owner["data"]) == 2

    mine =
      conn
      |> coach_conn(tenant, membership)
      |> get("/api/staff/feedback")
      |> json_response(200)

    assert [%{"body" => "Mine"} = row] = mine["data"]
    assert row["coach_id"] == membership.id
  end

  test "skill tags: coaches read, owners manage", %{conn: conn, tenant: tenant} do
    owner =
      conn
      |> staff_conn(tenant, :owner)
      |> json_post("/api/staff/feedback/skill_tags", %{
        "skill_tag" => %{"name" => "Dribbling", "slug" => "dribbling"}
      })
      |> json_response(201)

    assert owner["slug"] == "dribbling"

    tags =
      conn
      |> staff_conn(tenant, :owner)
      |> get("/api/staff/feedback/skill_tags")
      |> json_response(200)

    assert Enum.any?(tags["data"], &(&1["slug"] == "dribbling"))

    membership = coach(tenant)

    denied =
      conn
      |> coach_conn(tenant, membership)
      |> json_post("/api/staff/feedback/skill_tags", %{
        "skill_tag" => %{"name" => "X", "slug" => "x"}
      })
      |> json_response(403)

    assert denied["error"]["code"] == "forbidden"

    list =
      conn
      |> coach_conn(tenant, membership)
      |> get("/api/staff/feedback/skill_tags")
      |> json_response(200)

    assert is_list(list["data"])
  end

  ## Helpers

  defp coach(tenant) do
    email = "coach-#{System.unique_integer([:positive])}@example.com"
    {:ok, staff_user} = Staff.register_staff_user(%{email: email, password: "password1234"})
    {:ok, membership} = Staff.upsert_membership(tenant.id, staff_user.id, :coach)
    membership
  end

  defp coach_actor(tenant, membership) do
    StaffActor.new(
      staff_user_id: membership.staff_user_id,
      membership: membership,
      tenant_id: tenant.id,
      role: :coach
    )
  end

  defp coach_conn(conn, tenant, membership) do
    conn
    |> with_host(tenant.slug)
    |> Plug.Conn.assign(:current_staff_actor, coach_actor(tenant, membership))
    |> Plug.Conn.assign(:tenant, tenant)
  end

  defp assigned_session(venue, offering, membership, days_offset) do
    starts_at =
      DateTime.utc_now()
      |> DateTime.add(trunc(days_offset * 86_400), :second)
      |> DateTime.truncate(:microsecond)

    s =
      insert(:session,
        offering_id: offering.id,
        venue_id: venue.id,
        capacity: 5,
        starts_at: starts_at,
        ends_at: DateTime.add(starts_at, 3600, :second)
      )

    if membership do
      insert(:session_coach, session: s, membership_id: membership.id)
    end

    s
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

  defp json_patch(conn, path, payload) do
    conn
    |> put_req_header("content-type", "application/json")
    |> patch(path, Jason.encode!(payload))
  end
end
