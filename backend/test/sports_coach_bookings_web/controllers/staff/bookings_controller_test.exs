defmodule SportsCoachBookingsWeb.Staff.BookingsControllerTest do
  use SportsCoachBookingsWeb.ConnCase, async: false

  import Ecto.Query

  alias SportsCoachBookings.Credits
  alias SportsCoachBookings.Players
  alias SportsCoachBookings.Repo
  alias SportsCoachBookings.Scheduling.Session

  setup do
    tenant = insert(:tenant, slug: "staff-bookings-#{System.unique_integer([:positive])}")
    SportsCoachBookings.DataCase.put_tenant(tenant)
    venue = insert(:venue)
    %{tenant: tenant, venue: venue}
  end

  defp player(household) do
    {:ok, player} =
      Players.create_player(nil, %{
        household_id: household,
        first_name: "Test",
        last_name: "Player #{System.unique_integer([:positive])}",
        date_of_birth: ~D[2015-05-01]
      })

    {:ok, _} =
      Players.create_emergency_contact(player, %{
        name: "Parent",
        relationship: "Parent",
        phone: "+15555550100",
        priority: 1
      })

    player
  end

  defp session(venue, offering) do
    starts_at =
      DateTime.utc_now() |> DateTime.add(3, :day) |> DateTime.truncate(:microsecond)

    insert(:session,
      offering_id: offering.id,
      venue_id: venue.id,
      capacity: 5,
      starts_at: starts_at,
      ends_at: DateTime.add(starts_at, 3600, :second)
    )
  end

  defp json_post(conn, path, payload) do
    conn
    |> put_req_header("content-type", "application/json")
    |> post(path, Jason.encode!(payload))
  end

  test "an owner books on behalf, sees the roster and history, and marks attendance", %{
    conn: conn,
    tenant: tenant,
    venue: venue
  } do
    household = insert(:household).id
    offering = insert(:offering, credit_cost: 0)
    session = session(venue, offering)
    player = player(household)
    conn = staff_conn(conn, tenant, :owner)

    created =
      conn
      |> json_post("/api/staff/bookings", %{
        "player_id" => player.id,
        "session_id" => session.id,
        "method" => "comp"
      })
      |> json_response(201)

    assert created["status"] == "confirmed"

    roster = conn |> get("/api/staff/sessions/#{session.id}/roster") |> json_response(200)
    assert [%{"player_id" => player_id, "status" => "confirmed"}] = roster["data"]
    assert player_id == player.id

    history = conn |> get("/api/staff/bookings?session_id=#{session.id}") |> json_response(200)
    assert [%{"booking" => %{"id" => id}}] = history["data"]
    assert id == created["id"]

    shift_into_past(session.id)

    attended =
      conn
      |> json_post("/api/staff/bookings/#{created["id"]}/attendance", %{"status" => "attended"})
      |> json_response(200)

    assert attended["status"] == "attended"
  end

  test "a coach cannot book on behalf", %{conn: conn, tenant: tenant, venue: venue} do
    household = insert(:household).id
    offering = insert(:offering, credit_cost: 0)
    session = session(venue, offering)
    player = player(household)
    conn = staff_conn(conn, tenant, :coach)

    resp =
      conn
      |> json_post("/api/staff/bookings", %{
        "player_id" => player.id,
        "session_id" => session.id,
        "method" => "comp"
      })
      |> json_response(403)

    assert resp["error"]["code"] == "forbidden"
  end

  test "an owner cancels a booking with a credit return", %{
    conn: conn,
    tenant: tenant,
    venue: venue
  } do
    household = insert(:household).id
    offering = insert(:offering, credit_cost: 1)
    session = session(venue, offering)
    player = player(household)
    {:ok, _} = Credits.grant_complimentary(nil, household, %{amount: 5})
    conn = staff_conn(conn, tenant, :owner)

    created =
      conn
      |> json_post("/api/staff/bookings", %{
        "player_id" => player.id,
        "session_id" => session.id,
        "method" => "credits"
      })
      |> json_response(201)

    cancelled =
      conn
      |> json_post("/api/staff/bookings/#{created["id"]}/cancel", %{"reason" => "admin"})
      |> json_response(200)

    assert cancelled["status"] == "cancelled"
    assert cancelled["cancel_outcome"]["credit_outcome"] == "return"
  end

  defp shift_into_past(session_id) do
    past = DateTime.add(DateTime.utc_now(), -3600, :second) |> DateTime.truncate(:microsecond)

    Repo.update_all(
      from(s in Session, where: s.id == ^session_id),
      set: [starts_at: past, ends_at: DateTime.add(past, 3600, :second)]
    )
  end
end
