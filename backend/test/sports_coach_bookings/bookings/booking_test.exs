defmodule SportsCoachBookings.Bookings.BookingTest do
  use SportsCoachBookings.DataCase, async: false

  import Ecto.Query

  alias SportsCoachBookings.Bookings
  alias SportsCoachBookings.Bookings.Booking
  alias SportsCoachBookings.Bookings.BookingEvent
  alias SportsCoachBookings.Commerce.OrderLine
  alias SportsCoachBookings.Core.CustomerActor
  alias SportsCoachBookings.Core.StaffActor
  alias SportsCoachBookings.Credits
  alias SportsCoachBookings.Players
  alias SportsCoachBookings.Scheduling.Session
  alias SportsCoachBookings.Waivers

  setup do
    tenant = insert(:tenant)
    put_tenant(tenant)
    venue = insert(:venue)

    %{tenant: tenant, venue: venue, owner: owner(tenant)}
  end

  ## Book

  test "books with credits, consumes them, and increments booked_count", %{
    tenant: tenant,
    venue: venue,
    owner: owner
  } do
    household = insert(:household).id
    offering = insert(:offering, credit_cost: 1)
    session = session(venue, offering, at(3), 5)
    player = player(household)
    {:ok, _lot} = Credits.grant_complimentary(nil, household, %{amount: 5})

    assert {:ok, %Booking{status: :confirmed, credits_used: 1} = booking} =
             Bookings.book(owner, player.id, session.id, :credits)

    assert booking.payment_method == :credits
    assert booking.policy_snapshot["policy_name"]
    assert Repo.get!(Session, session.id).booked_count == 1
    assert Credits.available_for_offering(household, offering.id) == 4
    assert [%BookingEvent{kind: "confirmed"}] = Bookings.list_booking_events(booking.id)
    assert tenant.id == booking.tenant_id
  end

  test "a household manager books their own player", %{venue: venue, tenant: tenant} do
    household = insert(:household).id
    offering = insert(:offering, credit_cost: 1)
    session = session(venue, offering, at(3), 5)
    player = player(household)
    {:ok, _} = Credits.grant_complimentary(nil, household, %{amount: 1})

    actor =
      CustomerActor.new(
        customer_user_id: Ecto.UUID.generate(),
        household_id: household,
        tenant_id: tenant.id
      )

    assert {:ok, %Booking{}} = Bookings.book(actor, player.id, session.id, :credits)
  end

  test "rejects booking another household's player", %{venue: venue, tenant: tenant} do
    offering = insert(:offering, credit_cost: 1)
    session = session(venue, offering, at(3), 5)
    player = player(insert(:household).id)

    actor =
      CustomerActor.new(
        customer_user_id: Ecto.UUID.generate(),
        household_id: Ecto.UUID.generate(),
        tenant_id: tenant.id
      )

    assert {:error, :forbidden} = Bookings.book(actor, player.id, session.id, :credits)
  end

  ## Gates

  test "waiver gate blocks booking until signed", %{venue: venue, owner: owner} do
    household = insert(:household).id
    offering = insert(:offering, credit_cost: 0)
    session = session(venue, offering, at(3), 5)
    player = player(household)
    {:ok, _} = Credits.grant_complimentary(nil, household, %{amount: 1})

    {:ok, template} =
      Waivers.create_template(nil, %{name: "Liability", scope: "all_bookings"})

    {:ok, draft} = Waivers.create_version(nil, template.id, %{body_markdown: "Risk."})
    {:ok, published} = Waivers.publish_version(nil, draft.id)

    assert {:error, {:waivers_required, _message, %{waivers: [waiver]}}} =
             Bookings.book(owner, player.id, session.id, :credits)

    assert waiver["template_id"] == template.id

    {:ok, _signature} =
      Waivers.sign(nil, player.id, published.id, %{
        content_sha256: published.content_sha256,
        customer_user_id: Ecto.UUID.generate(),
        signer_name_typed: "Parent",
        signer_relationship: "Parent",
        consent_checkbox: true,
        ip: "127.0.0.1",
        user_agent: "test"
      })

    assert {:ok, %Booking{}} = Bookings.book(owner, player.id, session.id, :credits)
  end

  test "age gate blocks an ineligible player", %{venue: venue, owner: owner} do
    offering = insert(:offering, min_age: 7, max_age: 10, credit_cost: 0)
    session = session(venue, offering, at(3), 5)
    player = player(insert(:household).id, ~D[2021-01-01])
    {:ok, _} = Credits.grant_complimentary(nil, player.household_id, %{amount: 1})

    assert {:error, {:age_restricted, _message, %{min_age: 7}}} =
             Bookings.book(owner, player.id, session.id, :credits)
  end

  test "duplicate booking is rejected", %{venue: venue, owner: owner} do
    household = insert(:household).id
    offering = insert(:offering, credit_cost: 1)
    session = session(venue, offering, at(3), 5)
    player = player(household)
    {:ok, _} = Credits.grant_complimentary(nil, household, %{amount: 5})

    assert {:ok, %Booking{}} = Bookings.book(owner, player.id, session.id, :credits)

    assert {:error, {:already_booked, _message}} =
             Bookings.book(owner, player.id, session.id, :credits)
  end

  test "overlapping session is rejected", %{venue: venue, owner: owner} do
    household = insert(:household).id
    offering = insert(:offering, credit_cost: 1)
    first = session(venue, offering, at(3), 5)
    second = session(venue, offering, at(3), 5)
    player = player(household)
    {:ok, _} = Credits.grant_complimentary(nil, household, %{amount: 5})

    assert {:ok, %Booking{}} = Bookings.book(owner, player.id, first.id, :credits)

    assert {:error, {:player_conflict, _message}} =
             Bookings.book(owner, player.id, second.id, :credits)
  end

  test "booking window rejects too-late and too-early", %{venue: venue, owner: owner} do
    household = insert(:household).id
    offering = insert(:offering, credit_cost: 1, bookable_until_minutes_before: 60)
    late = session(venue, offering, DateTime.add(at(0), 30, :minute), 5)
    player = player(household)
    {:ok, _} = Credits.grant_complimentary(nil, household, %{amount: 5})

    assert {:error, {:too_late, _}} = Bookings.book(owner, player.id, late.id, :credits)

    offering_early = insert(:offering, credit_cost: 1, bookable_from_days_ahead: 1)
    early = session(venue, offering_early, at(5), 5)
    player2 = player(household)

    assert {:error, {:too_early, _}} = Bookings.book(owner, player2.id, early.id, :credits)
  end

  test "a full session is rejected with :session_full", %{venue: venue, owner: owner} do
    offering = insert(:offering, credit_cost: 0)
    session = session(venue, offering, at(3), 1)
    p1 = player(insert(:household).id)
    p2 = player(insert(:household).id)

    assert {:ok, %Booking{}} = Bookings.book(owner, p1.id, session.id, :comp)
    assert {:error, :session_full} = Bookings.book(owner, p2.id, session.id, :comp)
  end

  ## Cancel

  test "cancel returns credits when the policy tier allows", %{venue: venue, owner: owner} do
    household = insert(:household).id
    offering = insert(:offering, credit_cost: 1)
    session = session(venue, offering, at(3), 5)
    player = player(household)
    {:ok, _} = Credits.grant_complimentary(nil, household, %{amount: 5})
    {:ok, booking} = Bookings.book(owner, player.id, session.id, :credits)

    assert {:ok, cancelled} = Bookings.cancel(owner, booking.id, reason: "changed mind")
    assert cancelled.status == :cancelled
    assert cancelled.cancel_outcome["credit_outcome"] == "return"
    assert Repo.get!(Session, session.id).booked_count == 0
    assert Credits.available_for_offering(household, offering.id) == 5
  end

  test "late cancel forfeits credits", %{venue: venue, owner: owner} do
    household = insert(:household).id
    offering = insert(:offering, credit_cost: 1, bookable_until_minutes_before: 30)
    session = session(venue, offering, DateTime.add(at(0), 2, :hour), 5)
    player = player(household)
    {:ok, _} = Credits.grant_complimentary(nil, household, %{amount: 5})
    {:ok, booking} = Bookings.book(owner, player.id, session.id, :credits)

    assert {:ok, cancelled} = Bookings.cancel(owner, booking.id, [])
    assert cancelled.cancel_outcome["credit_outcome"] == "forfeit"
    assert Credits.available_for_offering(household, offering.id) == 4
  end

  test "a free-change window from a reschedule returns credits", %{venue: venue, owner: owner} do
    household = insert(:household).id
    offering = insert(:offering, credit_cost: 1, bookable_until_minutes_before: 30)
    session = session(venue, offering, DateTime.add(at(0), 2, :hour), 5)
    player = player(household)
    {:ok, _} = Credits.grant_complimentary(nil, household, %{amount: 5})
    {:ok, booking} = Bookings.book(owner, player.id, session.id, :credits)

    assert {:ok, 1} =
             Bookings.set_free_change(session.id, DateTime.add(DateTime.utc_now(), 7, :day))

    assert {:ok, cancelled} = Bookings.cancel(owner, booking.id, [])
    assert cancelled.cancel_outcome["credit_outcome"] == "return"
    assert Credits.available_for_offering(household, offering.id) == 5
  end

  test "staff override returns credits and is audited", %{venue: venue, owner: owner} do
    household = insert(:household).id
    offering = insert(:offering, credit_cost: 1, bookable_until_minutes_before: 30)
    session = session(venue, offering, DateTime.add(at(0), 2, :hour), 5)
    player = player(household)
    {:ok, _} = Credits.grant_complimentary(nil, household, %{amount: 5})
    {:ok, booking} = Bookings.book(owner, player.id, session.id, :credits)

    assert {:ok, cancelled} =
             Bookings.cancel(owner, booking.id,
               reason: "goodwill",
               outcome: :full_return
             )

    assert cancelled.cancel_outcome["credit_outcome"] == "return"
    assert Credits.available_for_offering(household, offering.id) == 5

    audit =
      Repo.all(
        from(e in SportsCoachBookings.Core.Audit.Event,
          where: e.action == "bookings.booking.cancelled_override"
        )
      )

    assert length(audit) == 1
  end

  test "a customer cannot override the cancellation outcome", %{venue: venue, tenant: tenant} do
    household = insert(:household).id
    offering = insert(:offering, credit_cost: 1)
    session = session(venue, offering, at(3), 5)
    player = player(household)
    {:ok, _} = Credits.grant_complimentary(nil, household, %{amount: 5})

    customer =
      CustomerActor.new(
        customer_user_id: Ecto.UUID.generate(),
        household_id: household,
        tenant_id: tenant.id
      )

    {:ok, booking} = Bookings.book(customer, player.id, session.id, :credits)

    assert {:error, :forbidden} =
             Bookings.cancel(customer, booking.id, outcome: :forfeit, reason: "x")

    assert Repo.get!(Booking, booking.id).status == :confirmed
  end

  test "cancel preview reports the outcome without applying it", %{venue: venue, owner: owner} do
    household = insert(:household).id
    offering = insert(:offering, credit_cost: 1)
    session = session(venue, offering, at(3), 5)
    player = player(household)
    {:ok, _} = Credits.grant_complimentary(nil, household, %{amount: 5})
    {:ok, booking} = Bookings.book(owner, player.id, session.id, :credits)

    assert {:ok, %{outcome: %{"credit_outcome" => "return"}}} =
             Bookings.cancel_preview(owner, booking.id)

    assert Repo.get!(Booking, booking.id).status == :confirmed
    assert Credits.available_for_offering(household, offering.id) == 4
  end

  ## Attendance

  test "no_show applies the policy outcome", %{venue: venue, owner: owner} do
    household = insert(:household).id
    offering = insert(:offering, credit_cost: 1)
    session = session(venue, offering, at(3), 5)
    player = player(household)
    {:ok, _} = Credits.grant_complimentary(nil, household, %{amount: 5})
    {:ok, booking} = Bookings.book(owner, player.id, session.id, :credits)
    shift_into_past(session.id)

    assert {:ok, no_show} = Bookings.mark_attendance(owner, booking.id, :no_show)
    assert no_show.status == :no_show
    assert no_show.cancel_outcome["credit_outcome"] == "forfeit"
    assert Credits.available_for_offering(household, offering.id) == 4
  end

  test "attended is recorded", %{venue: venue, owner: owner} do
    household = insert(:household).id
    offering = insert(:offering, credit_cost: 1)
    session = session(venue, offering, at(3), 5)
    player = player(household)
    {:ok, _} = Credits.grant_complimentary(nil, household, %{amount: 5})
    {:ok, booking} = Bookings.book(owner, player.id, session.id, :credits)
    shift_into_past(session.id)

    assert {:ok, attended} = Bookings.mark_attendance(owner, booking.id, :attended)
    assert attended.status == :attended
  end

  ## Provider cancel

  test "session cancellation returns credits with the provider outcome", %{
    venue: venue,
    owner: owner
  } do
    household = insert(:household).id
    offering = insert(:offering, credit_cost: 1)
    session = session(venue, offering, at(3), 5)
    player = player(household)
    {:ok, _} = Credits.grant_complimentary(nil, household, %{amount: 5})
    {:ok, _booking} = Bookings.book(owner, player.id, session.id, :credits)

    assert :ok = Bookings.cancel_for_session(session.id, reason: "weather")
    assert Credits.available_for_offering(household, offering.id) == 5
    assert Repo.get!(Session, session.id).booked_count == 0
  end

  ## Rebook

  test "rebook moves credits without a second debit", %{venue: venue, owner: owner} do
    household = insert(:household).id
    offering = insert(:offering, credit_cost: 1)
    source = session(venue, offering, at(3), 5)
    target = session(venue, offering, at(4), 5)
    player = player(household)
    {:ok, _} = Credits.grant_complimentary(nil, household, %{amount: 5})
    {:ok, booking} = Bookings.book(owner, player.id, source.id, :credits)

    assert {:ok, new_booking} = Bookings.rebook(owner, booking.id, target.id, [])
    assert new_booking.status == :confirmed
    assert new_booking.rebook_count == 1
    assert new_booking.rebooked_from_id == booking.id

    old = Repo.get!(Booking, booking.id)
    assert old.status == :cancelled
    assert old.rebooked_to_id == new_booking.id

    assert Repo.get!(Session, source.id).booked_count == 0
    assert Repo.get!(Session, target.id).booked_count == 1
    assert Credits.available_for_offering(household, offering.id) == 4
  end

  test "rebook honours the max-rebooks limit", %{venue: venue, owner: owner} do
    household = insert(:household).id
    offering = insert(:offering, credit_cost: 1)
    player = player(household)
    {:ok, _} = Credits.grant_complimentary(nil, household, %{amount: 5})

    s1 = session(venue, offering, at(3), 5)
    s2 = session(venue, offering, at(4), 5)
    s3 = session(venue, offering, at(5), 5)
    s4 = session(venue, offering, at(6), 5)

    {:ok, b1} = Bookings.book(owner, player.id, s1.id, :credits)
    {:ok, b2} = Bookings.rebook(owner, b1.id, s2.id, [])
    {:ok, b3} = Bookings.rebook(owner, b2.id, s3.id, [])

    assert {:error, {:rebook_not_allowed, "rebook_limit_reached"}} =
             Bookings.rebook(owner, b3.id, s4.id, [])
  end

  ## Holds

  test "a paid booking creates a hold and expiry releases the seat", %{
    venue: venue,
    owner: owner
  } do
    household = insert(:household).id
    offering = insert(:offering, drop_in_price: 10_000)
    session = session(venue, offering, at(3), 5)
    player = player(household)

    assert {:ok, %Booking{status: :held} = booking} =
             Bookings.book(owner, player.id, session.id, :paid)

    assert Repo.get!(Session, session.id).held_count == 1
    assert booking.hold_expires_at

    assert {:ok, 1} =
             Bookings.expire_due_holds(DateTime.add(booking.hold_expires_at, 60, :second))

    assert Repo.get!(Session, session.id).held_count == 0
    assert Repo.get!(Booking, booking.id).status == :cancelled
  end

  test "order.paid confirmation is idempotent", %{venue: venue, owner: owner} do
    household = insert(:household).id
    offering = insert(:offering, drop_in_price: 10_000)
    session = session(venue, offering, at(3), 5)
    player = player(household)

    {:ok, booking} = Bookings.book(owner, player.id, session.id, :paid)
    order = insert(:order, status: :paid, household_id: household)

    _line =
      insert(:order_line,
        order: order,
        type: :drop_in,
        ref_id: booking.id,
        booking_id: booking.id,
        unit_price: 10_000,
        line_total: 10_000,
        quantity: 1
      )

    assert :ok = Bookings.confirm_order_holds(order.id)
    assert Repo.get!(Session, session.id).held_count == 0
    assert Repo.get!(Session, session.id).booked_count == 1
    assert Repo.get!(Booking, booking.id).status == :confirmed

    assert :ok = Bookings.confirm_order_holds(order.id)
    assert Repo.get!(Session, session.id).booked_count == 1
  end

  test "order.expired releases the hold", %{venue: venue, owner: owner} do
    household = insert(:household).id
    offering = insert(:offering, drop_in_price: 10_000)
    session = session(venue, offering, at(3), 5)
    player = player(household)
    {:ok, booking} = Bookings.book(owner, player.id, session.id, :paid)
    order = insert(:order, status: :pending_payment, household_id: household)

    _line =
      insert(:order_line,
        order: order,
        type: :drop_in,
        ref_id: booking.id,
        booking_id: booking.id
      )

    assert :ok = Bookings.release_order_holds(order.id)
    assert Repo.get!(Session, session.id).held_count == 0
    assert Repo.get!(Booking, booking.id).status == :cancelled
  end

  test "partial card refund is applied on cancel", %{venue: venue, owner: owner} do
    household = insert(:household).id
    offering = insert(:offering, drop_in_price: 10_000)
    session = session(venue, offering, at(3), 5)
    player = player(household)
    {:ok, booking} = Bookings.book(owner, player.id, session.id, :paid)

    order = insert(:order, status: :paid, household_id: household)

    line =
      insert(:order_line,
        order: order,
        type: :drop_in,
        ref_id: booking.id,
        booking_id: booking.id,
        unit_price: 10_000,
        line_total: 10_000,
        quantity: 1
      )

    :ok = Bookings.confirm_order_holds(order.id)
    set_half_refund_snapshot(booking.id)

    assert {:ok, cancelled} = Bookings.cancel(owner, booking.id, [])
    assert cancelled.cancel_outcome["refund_amount"] == 5_000
    assert Repo.get!(OrderLine, line.id).refunded_amount == 5_000
  end

  ## Concurrency

  @tag timeout: 300_000
  test "50 concurrent bookings on a capacity-5 session yield exactly 5 (20 runs)", %{
    venue: venue,
    owner: owner,
    tenant: tenant
  } do
    # The SQL sandbox serialises statements onto one connection and the row
    # lock is re-entrant within the shared transaction, so parallelism is not
    # observable at the DB level. We still hammer the exact atomic path
    # (`Bookings.book` → lock + adjust) and assert exactly capacity succeed.
    offering = insert(:offering, credit_cost: 0)
    players = for _ <- 1..50, do: player(insert(:household).id)

    for run <- 1..20 do
      session = session(venue, offering, at(3 + run), 5)

      results =
        1..50
        |> Task.async_stream(
          fn index ->
            SportsCoachBookings.DataCase.put_tenant(tenant)
            Bookings.book(owner, Enum.at(players, index - 1).id, session.id, :comp)
          end,
          max_concurrency: 10,
          timeout: 60_000
        )
        |> Enum.map(fn {:ok, result} -> result end)

      successes = Enum.count(results, &match?({:ok, %Booking{status: :confirmed}}, &1))
      full = Enum.count(results, &match?({:error, :session_full}, &1))

      assert successes == 5, "run #{run}: expected 5 successes, got #{successes}"
      assert full == 45, "run #{run}: expected 45 session_full, got #{full}"

      fresh = Repo.get!(Session, session.id)
      assert fresh.booked_count == 5
      assert fresh.booked_count + fresh.held_count <= fresh.capacity

      assert Repo.aggregate(
               from(b in Booking, where: b.session_id == ^session.id and b.status == :confirmed),
               :count
             ) == 5
    end
  end

  ## Helpers

  defp owner(tenant) do
    StaffActor.new(staff_user_id: Ecto.UUID.generate(), tenant_id: tenant.id, role: :owner)
  end

  defp player(household_id, dob \\ ~D[2015-05-01]) do
    {:ok, player} =
      Players.create_player(nil, %{
        household_id: household_id,
        first_name: "Test",
        last_name: "Player #{System.unique_integer([:positive])}",
        date_of_birth: dob
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

  defp session(venue, offering, starts_at, capacity) do
    insert(:session,
      offering_id: offering.id,
      venue_id: venue.id,
      capacity: capacity,
      starts_at: starts_at,
      ends_at: DateTime.add(starts_at, 3600, :second)
    )
  end

  defp at(days) do
    DateTime.utc_now()
    |> DateTime.add(days * 86_400, :second)
    |> DateTime.truncate(:microsecond)
  end

  defp shift_into_past(session_id) do
    past = DateTime.add(DateTime.utc_now(), -3600, :second) |> DateTime.truncate(:microsecond)

    Repo.update_all(
      from(s in Session, where: s.id == ^session_id),
      set: [starts_at: past, ends_at: DateTime.add(past, 3600, :second)]
    )
  end

  defp set_half_refund_snapshot(booking_id) do
    snapshot = %{
      "policy_id" => nil,
      "policy_name" => "Half refund",
      "policy_version" => 1,
      "summary" => "",
      "rules" => %{
        "cancellation_tiers" => [
          %{"min_hours_before" => 0, "credit_outcome" => "forfeit", "money_refund_pct" => 50}
        ],
        "no_show" => %{"credit_outcome" => "forfeit", "money_refund_pct" => 0},
        "late_cancel_counts_as_no_show" => false,
        "rebook" => %{
          "allowed" => true,
          "min_hours_before" => 0,
          "max_rebooks_per_booking" => 2,
          "same_offering_only" => true
        },
        "provider_cancelled" => %{"credit_outcome" => "return", "money_refund_pct" => 100}
      }
    }

    Repo.update_all(
      from(b in Booking, where: b.id == ^booking_id),
      set: [policy_snapshot: snapshot]
    )
  end
end
