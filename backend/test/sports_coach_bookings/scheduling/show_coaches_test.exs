defmodule SportsCoachBookings.Scheduling.ShowCoachesTest do
  @moduledoc """
  Per-session `show_coaches` setting: admins control whether coach names appear
  publicly, and the portal must not receive them when disabled.
  """

  use SportsCoachBookings.DataCase, async: false

  alias SportsCoachBookings.Core.StaffActor
  alias SportsCoachBookings.Scheduling

  setup do
    tenant = insert(:tenant)
    put_tenant(tenant)

    actor =
      StaffActor.new(staff_user_id: Ecto.UUID.generate(), tenant_id: tenant.id, role: :owner)

    offering =
      insert(:offering,
        tenant_id: tenant.id,
        duration_minutes: 60,
        default_capacity: 5,
        bookable_until_minutes_before: 60
      )

    venue = insert(:venue, tenant_id: tenant.id, timezone: "America/Halifax")
    coach = insert(:membership, tenant_id: tenant.id, role: :coach)

    starts_at = DateTime.add(DateTime.utc_now(), 7, :day)

    %{
      tenant: tenant,
      actor: actor,
      offering: offering,
      venue: venue,
      coach: coach,
      starts_at: starts_at
    }
  end

  defp create(actor, offering, venue, coach, show_coaches) do
    # String keys mirror an HTTP JSON body, exercising the controller path.
    attrs = %{
      "offering_id" => offering.id,
      "venue_id" => venue.id,
      "starts_at" => DateTime.to_iso8601(DateTime.add(DateTime.utc_now(), 7, :day)),
      "capacity" => 5,
      "show_coaches" => show_coaches,
      "coach_ids" => [coach.id]
    }

    assert {:ok, %{session: session}} = Scheduling.create_session(actor, attrs)
    session
  end

  test "portal hides coach names when show_coaches is false", %{
    actor: actor,
    offering: offering,
    venue: venue,
    coach: coach
  } do
    session = create(actor, offering, venue, coach, false)

    assert session.show_coaches == false

    assert {:ok, entry} = Scheduling.portal_session(session.id)
    assert entry.coaches == []
  end

  test "portal shows coach names when show_coaches is true", %{
    actor: actor,
    offering: offering,
    venue: venue,
    coach: coach
  } do
    session = create(actor, offering, venue, coach, true)

    assert session.show_coaches == true

    assert {:ok, entry} = Scheduling.portal_session(session.id)
    assert entry.coaches != []
    assert Enum.any?(entry.coaches, &(&1.id == coach.id))
  end

  test "staff still see coaches even when hidden from the portal", %{
    actor: actor,
    offering: offering,
    venue: venue,
    coach: coach
  } do
    session = create(actor, offering, venue, coach, false)

    assert {:ok, entry} = Scheduling.session_detail(session.id)
    assert Enum.any?(entry.coaches, &(&1.id == coach.id))
  end

  test "show_coaches can be toggled after creation (HTTP string keys)", %{
    actor: actor,
    offering: offering,
    venue: venue,
    coach: coach
  } do
    session = create(actor, offering, venue, coach, true)

    assert {:ok, %{session: updated}} =
             Scheduling.update_session(actor, session.id, %{"show_coaches" => false})

    assert updated.show_coaches == false

    assert {:ok, entry} = Scheduling.portal_session(session.id)
    assert entry.coaches == []
  end

  test "capacity updates via string keys persist (update regression)", %{
    actor: actor,
    offering: offering,
    venue: venue,
    coach: coach
  } do
    session = create(actor, offering, venue, coach, true)

    assert {:ok, %{session: updated}} =
             Scheduling.update_session(actor, session.id, %{
               "capacity" => 3,
               "notes_public" => "Bring water"
             })

    assert updated.capacity == 3
    assert updated.notes_public == "Bring water"
  end

  test "series edits via string keys persist (edit_series regression)", %{
    actor: actor,
    offering: offering,
    venue: venue,
    coach: coach
  } do
    series_attrs = %{
      "offering_id" => offering.id,
      "venue_id" => venue.id,
      "weekdays" => [2],
      "start_time_local" => "17:00",
      "duration_minutes" => 60,
      "starts_on" => Date.to_iso8601(Date.add(Date.utc_today(), 7)),
      "ends_on" => Date.to_iso8601(Date.add(Date.utc_today(), 28)),
      "capacity" => 5,
      "coach_ids" => [coach.id]
    }

    assert {:ok, %{series: series, sessions: [first | _]}} =
             Scheduling.create_series(actor, series_attrs)

    assert {:ok, result} =
             Scheduling.update_series(actor, :all, series.id, %{"capacity" => 2})

    assert Enum.all?(result.sessions, &(&1.capacity == 2))
    assert Repo.reload!(first).capacity == 2
  end
end
