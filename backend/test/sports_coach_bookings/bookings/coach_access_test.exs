defmodule SportsCoachBookings.Bookings.CoachAccessTest do
  use SportsCoachBookings.DataCase, async: false

  alias SportsCoachBookings.Bookings
  alias SportsCoachBookings.Bookings.CoachAccess
  alias SportsCoachBookings.Core.StaffActor
  alias SportsCoachBookings.Players
  alias SportsCoachBookings.Staff

  setup do
    CoachAccess.reset_cache()
    tenant = insert(:tenant)
    put_tenant(tenant)
    venue = insert(:venue)

    %{tenant: tenant, venue: venue}
  end

  test "owners and admins always see players", %{tenant: tenant} do
    for role <- [:owner, :admin] do
      actor =
        StaffActor.new(staff_user_id: Ecto.UUID.generate(), tenant_id: tenant.id, role: role)

      assert CoachAccess.player_visible?(actor, Ecto.UUID.generate())
    end
  end

  test "a coach sees a player booked into a session they coach", %{
    tenant: tenant,
    venue: venue
  } do
    coach = coach_membership(tenant)
    offering = insert(:offering)
    session = session_in_window(offering, venue)
    insert(:session_coach, session: session, membership_id: coach.id)

    household = insert(:household).id
    player_row = player(household)
    insert(:booking, session_id: session.id, player_id: player_row.id, household_id: household)

    actor = coach_actor(tenant, coach)
    assert CoachAccess.player_visible?(actor, player_row.id)
  end

  test "a coach does not see a player with no booking in their sessions", %{
    tenant: tenant,
    venue: venue
  } do
    coach = coach_membership(tenant)
    offering = insert(:offering)
    _session = insert(:session, offering_id: offering.id, venue_id: venue.id, capacity: 5)
    actor = coach_actor(tenant, coach)

    assert CoachAccess.player_visible?(actor, Ecto.UUID.generate()) == false
  end

  test "a coach does not see a player booked only into another coach's session", %{
    tenant: tenant,
    venue: venue
  } do
    coach = coach_membership(tenant)
    other_coach = coach_membership(tenant)
    offering = insert(:offering)

    their_session = session_in_window(offering, venue)
    insert(:session_coach, session: their_session, membership_id: other_coach.id)

    _mine = session_in_window(offering, venue)

    household = insert(:household).id
    player_row = player(household)

    insert(:booking,
      session_id: their_session.id,
      player_id: player_row.id,
      household_id: household
    )

    assert CoachAccess.player_visible?(coach_actor(tenant, coach), player_row.id) == false
  end

  test "the visibility window is 30 days before to 90 days after the session", %{
    tenant: tenant,
    venue: venue
  } do
    coach = coach_membership(tenant)
    offering = insert(:offering)
    actor = coach_actor(tenant, coach)

    for {days, expected} <- [{20, true}, {-50, true}, {40, false}, {-100, false}] do
      player_row = player(insert(:household).id)
      assert visible_with_session_at?(actor, player_row, offering, venue, coach, days) == expected
    end
  end

  test "a real booking made through the engine is visible to the session coach", %{
    tenant: tenant,
    venue: venue
  } do
    coach = coach_membership(tenant)
    offering = insert(:offering, credit_cost: 0)
    starts_at = DateTime.utc_now() |> DateTime.add(4, :day) |> DateTime.truncate(:microsecond)

    session =
      insert(:session,
        offering_id: offering.id,
        venue_id: venue.id,
        capacity: 5,
        starts_at: starts_at,
        ends_at: DateTime.add(starts_at, 3600, :second)
      )

    insert(:session_coach, session: session, membership_id: coach.id)

    household = insert(:household).id
    player_row = player(household)

    owner =
      StaffActor.new(staff_user_id: Ecto.UUID.generate(), tenant_id: tenant.id, role: :owner)

    {:ok, _booking} = Bookings.book(owner, player_row.id, session.id, :comp)

    assert CoachAccess.player_visible?(coach_actor(tenant, coach), player_row.id)
  end

  ## Helpers

  defp session_in_window(offering, venue) do
    starts_at =
      DateTime.utc_now() |> DateTime.add(4, :day) |> DateTime.truncate(:microsecond)

    insert(:session,
      offering_id: offering.id,
      venue_id: venue.id,
      capacity: 5,
      starts_at: starts_at,
      ends_at: DateTime.add(starts_at, 3600, :second)
    )
  end

  defp visible_with_session_at?(actor, player_row, offering, venue, coach, days) do
    starts_at =
      DateTime.utc_now()
      |> DateTime.add(days * 86_400, :second)
      |> DateTime.truncate(:microsecond)

    session =
      insert(:session,
        offering_id: offering.id,
        venue_id: venue.id,
        capacity: 5,
        starts_at: starts_at,
        ends_at: DateTime.add(starts_at, 3600, :second)
      )

    insert(:session_coach, session: session, membership_id: coach.id)

    insert(:booking,
      session_id: session.id,
      player_id: player_row.id,
      household_id: player_row.household_id
    )

    result = CoachAccess.player_visible?(actor, player_row.id)
    CoachAccess.reset_cache()
    result
  end

  defp coach_membership(tenant) do
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

  defp player(household_id) do
    {:ok, player} =
      Players.create_player(nil, %{
        household_id: household_id,
        first_name: "Test",
        last_name: "Player #{System.unique_integer([:positive])}",
        date_of_birth: ~D[2015-05-01]
      })

    {:ok, _contact} =
      Players.create_emergency_contact(player, %{
        name: "Parent",
        relationship: "Parent",
        phone: "+15555550100",
        priority: 1
      })

    player
  end
end
