defmodule SportsCoachBookings.SchedulingTest do
  use SportsCoachBookings.DataCase, async: false

  import Ecto.Query

  alias SportsCoachBookings.Core.StaffActor
  alias SportsCoachBookings.Scheduling
  alias SportsCoachBookings.Scheduling.Seats

  defp event_names do
    Repo.all(from j in Oban.Job, select: j.args["name"])
  end

  defp local_hour(utc, timezone) do
    utc
    |> DateTime.shift_zone!(timezone)
    |> Map.take([:hour, :minute])
    |> then(&{&1.hour, &1.minute})
  end

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

    %{tenant: tenant, actor: actor, offering: offering, venue: venue, coach: coach}
  end

  describe "create_session/2" do
    test "creates a session with defaults from the offering", %{
      actor: actor,
      offering: offering,
      venue: venue
    } do
      {:ok, %{session: session, warnings: warnings}} =
        Scheduling.create_session(actor, %{
          offering_id: offering.id,
          venue_id: venue.id,
          starts_at: "2026-04-01T17:00:00Z"
        })

      assert session.capacity == 5
      assert session.status == :scheduled
      assert session.visibility == :public
      assert DateTime.diff(session.ends_at, session.starts_at, :minute) == 60
      assert warnings == []
    end

    test "assigns coaches", %{actor: actor, offering: offering, venue: venue, coach: coach} do
      {:ok, %{session: session}} =
        Scheduling.create_session(actor, %{
          offering_id: offering.id,
          venue_id: venue.id,
          starts_at: "2026-04-01T17:00:00Z",
          coach_ids: [coach.id]
        })

      assert [%{membership_id: membership_id, lead: true}] = session.session_coaches
      assert membership_id == coach.id
    end

    test "rejects an unknown coach", %{actor: actor, offering: offering, venue: venue} do
      assert {:error, {:invalid_coach, _}} =
               Scheduling.create_session(actor, %{
                 offering_id: offering.id,
                 venue_id: venue.id,
                 starts_at: "2026-04-01T17:00:00Z",
                 coach_ids: [Ecto.UUID.generate()]
               })
    end

    test "warns (does not block) on venue overlap", %{
      actor: actor,
      offering: offering,
      venue: venue
    } do
      base = %{offering_id: offering.id, venue_id: venue.id}

      {:ok, %{session: _first}} =
        Scheduling.create_session(actor, Map.put(base, :starts_at, "2026-04-01T17:00:00Z"))

      {:ok, %{session: _second, warnings: warnings}} =
        Scheduling.create_session(actor, Map.put(base, :starts_at, "2026-04-01T17:30:00Z"))

      assert [%{type: :venue_overlap}] = warnings
    end

    test "warns on coach double-booking", %{
      actor: actor,
      offering: offering,
      venue: venue,
      coach: coach
    } do
      another_venue = insert(:venue, tenant_id: actor.tenant_id, timezone: "America/Halifax")

      {:ok, %{session: _first}} =
        Scheduling.create_session(actor, %{
          offering_id: offering.id,
          venue_id: venue.id,
          starts_at: "2026-04-01T17:00:00Z",
          coach_ids: [coach.id]
        })

      {:ok, %{warnings: warnings}} =
        Scheduling.create_session(actor, %{
          offering_id: offering.id,
          venue_id: another_venue.id,
          starts_at: "2026-04-01T17:30:00Z",
          coach_ids: [coach.id]
        })

      assert Enum.any?(warnings, &(&1.type == :coach_double_booked))
      assert Enum.any?(warnings, &(&1.membership_id == coach.id))
    end
  end

  describe "create_series/2" do
    test "materialises DST-safe occurrences", %{
      actor: actor,
      offering: offering,
      venue: venue,
      coach: coach
    } do
      {:ok, %{series: series, sessions: sessions}} =
        Scheduling.create_series(actor, %{
          offering_id: offering.id,
          venue_id: venue.id,
          weekdays: [2],
          start_time_local: "17:00",
          duration_minutes: 60,
          starts_on: "2026-03-01",
          ends_on: "2026-03-15",
          coach_ids: [coach.id]
        })

      assert length(sessions) == 2
      assert Enum.all?(sessions, &(&1.series_id == series.id))

      starts = sessions |> Enum.map(& &1.starts_at) |> Enum.sort(DateTime)
      assert [~U[2026-03-03 21:00:00.000000Z], ~U[2026-03-10 20:00:00.000000Z]] = starts
      assert Enum.all?(starts, &(local_hour(&1, "America/Halifax") == {17, 0}))
      assert Enum.all?(sessions, &(&1.session_coaches != []))
    end

    test "rejects a range over the cap", %{actor: actor, offering: offering, venue: venue} do
      assert {:error, :too_many_occurrences} =
               Scheduling.create_series(actor, %{
                 offering_id: offering.id,
                 venue_id: venue.id,
                 weekdays: [1, 2, 3, 4, 5, 6, 7],
                 start_time_local: "09:00",
                 duration_minutes: 60,
                 starts_on: "2026-01-01",
                 ends_on: "2027-12-31"
               })
    end
  end

  describe "update_session/4 and cancel" do
    setup %{actor: actor, offering: offering, venue: venue} do
      {:ok, %{session: session}} =
        Scheduling.create_session(actor, %{
          offering_id: offering.id,
          venue_id: venue.id,
          starts_at: "2026-04-01T17:00:00Z",
          capacity: 5
        })

      %{session: session}
    end

    test "refuses capacity below the bookings", %{actor: actor, session: session} do
      {:ok, _} =
        Repo.with_tenant_tx(fn ->
          locked = Seats.lock_session!(session.id)
          Seats.adjust!(locked, 4, 0)
        end)

      assert {:error, {:capacity_below_bookings, 4}} =
               Scheduling.update_session(actor, session.id, %{capacity: 3})
    end

    test "publishes session.rescheduled when a booked session moves", %{
      actor: actor,
      session: session
    } do
      {:ok, _} =
        Repo.with_tenant_tx(fn ->
          locked = Seats.lock_session!(session.id)
          Seats.adjust!(locked, 1, 0)
        end)

      assert {:ok, %{session: updated}} =
               Scheduling.reschedule_session(actor, session.id, %{
                 starts_at: "2026-04-01T19:00:00Z",
                 ends_at: "2026-04-01T20:00:00Z"
               })

      assert updated.starts_at == ~U[2026-04-01 19:00:00.000000Z]
      assert "session.rescheduled" in event_names()
    end

    test "cancel publishes session.cancelled and reports impact", %{
      actor: actor,
      session: session
    } do
      {:ok, _} =
        Repo.with_tenant_tx(fn ->
          locked = Seats.lock_session!(session.id)
          Seats.adjust!(locked, 2, 1)
        end)

      assert {:ok, %{session: cancelled, impact: impact}} =
               Scheduling.cancel_session(actor, session.id, "weather")

      assert cancelled.status == :cancelled
      assert cancelled.cancel_reason == "weather"
      assert impact == %{booked_count: 2, held_count: 1}
      assert "session.cancelled" in event_names()
    end

    test "cancelling twice does not republish", %{actor: actor, session: session} do
      {:ok, _} = Scheduling.cancel_session(actor, session.id, "first")
      {:ok, _} = Scheduling.cancel_session(actor, session.id, "second")

      assert Enum.count(event_names(), &(&1 == "session.cancelled")) == 1
    end
  end

  describe "update_series/5" do
    setup %{actor: actor, offering: offering, venue: venue, coach: coach} do
      {:ok, %{series: series, sessions: sessions}} =
        Scheduling.create_series(actor, %{
          offering_id: offering.id,
          venue_id: venue.id,
          weekdays: [2],
          start_time_local: "17:00",
          duration_minutes: 60,
          starts_on: "2026-03-01",
          ends_on: "2026-03-31",
          coach_ids: [coach.id]
        })

      %{series: series, sessions: sessions}
    end

    test "single scope touches only one occurrence", %{actor: actor, sessions: [first | _]} do
      assert {:ok, %{sessions: [updated]}} =
               Scheduling.update_series(actor, :single, first.id, %{notes_public: "hello"})

      assert updated.id == first.id
      assert updated.notes_public == "hello"

      others =
        Scheduling.list_sessions(%{
          offering_id: first.offering_id,
          from: "2026-01-01T00:00:00Z",
          to: "2026-12-31T00:00:00Z"
        })

      assert Enum.map(Enum.filter(others, &(&1.notes_public == "hello")), & &1.id) == [updated.id]
    end

    test "following scope updates this and later occurrences", %{
      actor: actor,
      sessions: [first | _] = all
    } do
      assert {:ok, %{sessions: updated}} =
               Scheduling.update_series(actor, :following, first.id, %{capacity: 10})

      assert length(updated) == length(all)
      assert Enum.all?(updated, &(&1.capacity == 10))
    end

    test "all scope updates every occurrence", %{actor: actor, series: series} do
      assert {:ok, %{sessions: updated}} =
               Scheduling.update_series(actor, :all, series.id, %{capacity: 12})

      assert Enum.all?(updated, &(&1.capacity == 12))
    end

    test "requires confirmation when a targeted occurrence has bookings", %{
      actor: actor,
      sessions: [first | _]
    } do
      {:ok, _} =
        Repo.with_tenant_tx(fn ->
          Seats.adjust!(Seats.lock_session!(first.id), 1, 0)
        end)

      assert {:error, {:bookings_exist, 1}} =
               Scheduling.update_series(actor, :following, first.id, %{start_time_local: "18:00"})

      assert {:ok, %{sessions: updated}} =
               Scheduling.update_series(actor, :following, first.id, %{start_time_local: "18:00"},
                 confirm: true
               )

      assert Enum.all?(updated, &(local_hour(&1.starts_at, "America/Halifax") == {18, 0}))
    end
  end

  describe "calendar and portal" do
    test "portal returns only upcoming public bookable sessions", %{
      actor: actor,
      offering: offering,
      venue: venue
    } do
      future = DateTime.utc_now() |> DateTime.add(3, :day) |> DateTime.to_iso8601()

      {:ok, %{session: bookable}} =
        Scheduling.create_session(actor, %{
          offering_id: offering.id,
          venue_id: venue.id,
          starts_at: future
        })

      {:ok, %{session: hidden}} =
        Scheduling.create_session(actor, %{
          offering_id: offering.id,
          venue_id: venue.id,
          starts_at: future,
          visibility: :hidden
        })

      entries = Scheduling.portal_sessions(%{})

      assert Enum.any?(entries, &(&1.session.id == bookable.id))
      refute Enum.any?(entries, &(&1.session.id == hidden.id))
    end

    test "reports :full when there are no seats left", %{
      actor: actor,
      offering: offering,
      venue: venue
    } do
      future = DateTime.utc_now() |> DateTime.add(3, :day) |> DateTime.to_iso8601()

      {:ok, %{session: session}} =
        Scheduling.create_session(actor, %{
          offering_id: offering.id,
          venue_id: venue.id,
          starts_at: future,
          capacity: 1
        })

      {:ok, _} =
        Repo.with_tenant_tx(fn -> Seats.hold(session.id) end)

      [entry] = Scheduling.portal_sessions(%{})
      assert entry.seats_left == 0
      assert entry.not_bookable_reason == :full
      refute entry.bookable
    end
  end

  describe "Seats" do
    test "hold, confirm, release keep counters consistent", %{
      actor: actor,
      offering: offering,
      venue: venue
    } do
      {:ok, %{session: session}} =
        Scheduling.create_session(actor, %{
          offering_id: offering.id,
          venue_id: venue.id,
          starts_at: "2026-04-01T17:00:00Z",
          capacity: 3
        })

      {:ok, {:ok, held}} = Repo.with_tenant_tx(fn -> Seats.hold(session.id) end)
      assert {held.booked_count, held.held_count} == {0, 1}

      {:ok, {:ok, confirmed}} = Repo.with_tenant_tx(fn -> Seats.confirm_hold(session.id) end)
      assert {confirmed.booked_count, confirmed.held_count} == {1, 0}

      {:ok, {:ok, released}} = Repo.with_tenant_tx(fn -> Seats.release_booking(session.id) end)
      assert {released.booked_count, released.held_count} == {0, 0}
    end
  end

  describe "mark_completed/1" do
    test "completes past sessions only", %{actor: actor, offering: offering, venue: venue} do
      past = DateTime.utc_now() |> DateTime.add(-2, :day) |> DateTime.to_iso8601()
      future = DateTime.utc_now() |> DateTime.add(2, :day) |> DateTime.to_iso8601()

      {:ok, %{session: old}} =
        Scheduling.create_session(actor, %{
          offering_id: offering.id,
          venue_id: venue.id,
          starts_at: past
        })

      {:ok, %{session: upcoming}} =
        Scheduling.create_session(actor, %{
          offering_id: offering.id,
          venue_id: venue.id,
          starts_at: future
        })

      assert {:ok, count} = Scheduling.mark_completed()
      assert count == 1
      assert Scheduling.get_session!(old.id).status == :completed
      assert Scheduling.get_session!(upcoming.id).status == :scheduled
    end
  end
end
