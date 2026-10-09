defmodule SportsCoachBookings.Bookings.InvitationsTest do
  use SportsCoachBookings.DataCase, async: false

  alias SportsCoachBookings.Bookings
  alias SportsCoachBookings.Bookings.Booking
  alias SportsCoachBookings.Core.CustomerActor
  alias SportsCoachBookings.Core.StaffActor
  alias SportsCoachBookings.Credits
  alias SportsCoachBookings.Notifications
  alias SportsCoachBookings.Players
  alias SportsCoachBookings.Scheduling.Session

  setup do
    tenant = insert(:tenant)
    put_tenant(tenant)
    venue = insert(:venue)

    offering =
      insert(:offering,
        public_enabled: true,
        public_max_players: 2,
        public_players_per_coach: 2,
        public_price_tiers: %{"2" => %{"price" => 4_000, "credit_cost" => 1}},
        private_enabled: true,
        private_max_players: 4,
        private_players_per_coach: 4,
        private_price_tiers: %{"4" => %{"price" => 3_000, "credit_cost" => 1}},
        allow_invite_reservations: true,
        invite_hold_hours: 48,
        allow_private_conversion: true,
        allow_private_requests: true
      )

    %{tenant: tenant, venue: venue, offering: offering}
  end

  test "a split invitation transfers its reserved seat atomically on acceptance", ctx do
    inviter = household_actor(ctx.tenant)
    invitee = household_actor(ctx.tenant)
    inviter_player = player(inviter.household_id)
    invitee_player = player(invitee.household_id)
    session = session(ctx, days_from_now(4), 2)

    {:ok, _} = Credits.grant_complimentary(nil, inviter.household_id, %{amount: 2})
    {:ok, _} = Credits.grant_complimentary(nil, invitee.household_id, %{amount: 2})
    assert {:ok, %Booking{}} = Bookings.book(inviter, inviter_player.id, session.id, :credits)

    assert {:ok, %{invitation: invitation, token: token, booking: nil}} =
             Bookings.invite(inviter, session.id, %{
               email: invitee.customer_user.email,
               payment_mode: :split
             })

    assert invitation.expires_at
    assert %{booked_count: 1, held_count: 1} = Repo.get!(Session, session.id)

    assert {:ok, %{invitation: accepted, booking: booking}} =
             Bookings.accept_invitation(invitee, token, invitee_player.id, :credits)

    assert accepted.status == :accepted
    assert booking.player_id == invitee_player.id
    assert %{booked_count: 2, held_count: 0} = Repo.get!(Session, session.id)
  end

  test "inside the reservation window split holds close but purchased guest spaces remain allowed",
       ctx do
    inviter = household_actor(ctx.tenant)
    invitee = household_actor(ctx.tenant)
    inviter_player = player(inviter.household_id)
    invitee_player = player(invitee.household_id)
    session = session(ctx, DateTime.add(now(), 24, :hour), 2)

    {:ok, _} = Credits.grant_complimentary(nil, inviter.household_id, %{amount: 3})
    assert {:ok, %Booking{}} = Bookings.book(inviter, inviter_player.id, session.id, :credits)

    assert {:error, {:invite_hold_closed, _message}} =
             Bookings.invite(inviter, session.id, %{
               email: invitee.customer_user.email,
               payment_mode: :split
             })

    assert {:ok, %{invitation: invitation, token: token, booking: sponsored}} =
             Bookings.invite(inviter, session.id, %{
               email: invitee.customer_user.email,
               payment_mode: :organizer,
               method: :credits
             })

    assert invitation.expires_at == nil
    assert sponsored.status == :confirmed
    assert sponsored.player_id == nil

    assert {:ok, %{booking: assigned}} =
             Bookings.accept_invitation(invitee, token, invitee_player.id, :paid)

    assert assigned.player_id == invitee_player.id
    assert assigned.beneficiary_household_id == invitee.household_id
    assert %{booked_count: 2, held_count: 0} = Repo.get!(Session, session.id)
  end

  test "previous partners work for both the inviter and the invitee", ctx do
    inviter = household_actor(ctx.tenant)
    invitee = household_actor(ctx.tenant)
    inviter_player = player(inviter.household_id)
    invitee_player = player(invitee.household_id)
    session = session(ctx, days_from_now(4), 2)

    {:ok, _} = Credits.grant_complimentary(nil, inviter.household_id, %{amount: 2})
    {:ok, _} = Credits.grant_complimentary(nil, invitee.household_id, %{amount: 2})
    assert {:ok, %Booking{}} = Bookings.book(inviter, inviter_player.id, session.id, :credits)

    assert {:ok, %{token: token}} =
             Bookings.invite(inviter, session.id, %{
               email: invitee.customer_user.email,
               payment_mode: :split
             })

    assert {:ok, _result} =
             Bookings.accept_invitation(invitee, token, invitee_player.id, :credits)

    assert [%{email: invitee_email}] = Bookings.invitation_partners(inviter.household_id)
    assert invitee_email == invitee.customer_user.email

    assert [%{email: inviter_email}] = Bookings.invitation_partners(invitee.household_id)
    assert inviter_email == inviter.customer_user.email
  end

  test "an organizer can revoke a split invitation and release its seat", ctx do
    inviter = household_actor(ctx.tenant)
    invitee = household_actor(ctx.tenant)
    inviter_player = player(inviter.household_id)
    session = session(ctx, days_from_now(4), 2)

    {:ok, _} = Credits.grant_complimentary(nil, inviter.household_id, %{amount: 2})
    assert {:ok, %Booking{}} = Bookings.book(inviter, inviter_player.id, session.id, :credits)

    assert {:ok, %{invitation: invitation}} =
             Bookings.invite(inviter, session.id, %{
               email: invitee.customer_user.email,
               payment_mode: :split
             })

    assert %{held_count: 1} = Repo.get!(Session, session.id)
    assert {:ok, cancelled} = Bookings.cancel_invitation(inviter, invitation.id)
    assert cancelled.status == :cancelled
    assert cancelled.seat_status == :released
    assert %{booked_count: 1, held_count: 0} = Repo.get!(Session, session.id)
  end

  test "revoking an organizer-funded invitation returns its credit", ctx do
    inviter = household_actor(ctx.tenant)
    invitee = household_actor(ctx.tenant)
    inviter_player = player(inviter.household_id)
    session = session(ctx, days_from_now(4), 2)

    {:ok, _} = Credits.grant_complimentary(nil, inviter.household_id, %{amount: 3})
    assert {:ok, %Booking{}} = Bookings.book(inviter, inviter_player.id, session.id, :credits)

    assert {:ok, %{invitation: invitation}} =
             Bookings.invite(inviter, session.id, %{
               email: invitee.customer_user.email,
               payment_mode: :organizer,
               method: :credits
             })

    assert credit_balance(inviter.household_id) == 1
    assert {:ok, cancelled} = Bookings.cancel_invitation(inviter, invitation.id)
    assert cancelled.status == :cancelled
    assert credit_balance(inviter.household_id) == 2
    assert %{booked_count: 1, held_count: 0} = Repo.get!(Session, session.id)
  end

  test "resending rotates the token and invalidates the previous link", ctx do
    inviter = household_actor(ctx.tenant)
    invitee = household_actor(ctx.tenant)
    inviter_player = player(inviter.household_id)
    invitee_player = player(invitee.household_id)
    session = session(ctx, days_from_now(4), 2)

    {:ok, _} = Credits.grant_complimentary(nil, inviter.household_id, %{amount: 2})
    {:ok, _} = Credits.grant_complimentary(nil, invitee.household_id, %{amount: 2})
    assert {:ok, %Booking{}} = Bookings.book(inviter, inviter_player.id, session.id, :credits)

    assert {:ok, %{invitation: invitation, token: old_token}} =
             Bookings.invite(inviter, session.id, %{
               email: invitee.customer_user.email,
               payment_mode: :split
             })

    assert {:ok, %{invitation: resent, token: new_token}} =
             Bookings.resend_invitation(inviter, invitation.id)

    assert resent.resend_count == 1
    assert resent.last_sent_at
    refute old_token == new_token
    assert {:error, :not_found} = Bookings.invitation_by_token(old_token)

    assert {:ok, %{invitation: accepted}} =
             Bookings.accept_invitation(invitee, new_token, invitee_player.id, :credits)

    assert accepted.status == :accepted
  end

  test "invitations cannot exceed the mode maximum even if occurrence capacity is larger", ctx do
    inviter = household_actor(ctx.tenant)
    first_invitee = household_actor(ctx.tenant)
    second_invitee = household_actor(ctx.tenant)
    inviter_player = player(inviter.household_id)
    session = session(ctx, days_from_now(4), 4)

    {:ok, _} = Credits.grant_complimentary(nil, inviter.household_id, %{amount: 2})
    assert {:ok, %Booking{}} = Bookings.book(inviter, inviter_player.id, session.id, :credits)

    assert {:ok, _result} =
             Bookings.invite(inviter, session.id, %{
               email: first_invitee.customer_user.email,
               payment_mode: :split
             })

    assert {:error, :session_full} =
             Bookings.invite(inviter, session.id, %{
               email: second_invitee.customer_user.email,
               payment_mode: :split
             })
  end

  test "an empty public session can increase to the configured private capacity", ctx do
    actor = household_actor(ctx.tenant)
    session = session(ctx, days_from_now(4), 2)
    coach = insert(:membership, role: :coach)
    insert(:session_coach, session: session, membership_id: coach.id)

    assert {:ok, converted} = Bookings.convert_session_to_private(actor, session.id, 4)
    assert converted.access_mode == :private
    assert converted.capacity == 4
    assert converted.party_size == 4
    assert converted.exclusive_household_id == actor.household_id
  end

  test "a private conversion is capped at its selected price tier, not the private maximum",
       ctx do
    actor = household_actor(ctx.tenant)
    session = session(ctx, days_from_now(4), 2)

    assert {:ok, converted} = Bookings.convert_session_to_private(actor, session.id, 3)
    assert converted.capacity == 3
    assert converted.party_size == 3
  end

  test "private bookings use the selected party-size price tier", ctx do
    actor = household_actor(ctx.tenant)
    player = player(actor.household_id)
    session = session(ctx, days_from_now(4), 2)

    ctx.offering
    |> Ecto.Changeset.change(%{
      private_price_tiers: %{
        "1" => %{"price" => 8_000, "credit_cost" => 4},
        "2" => %{"price" => 6_000, "credit_cost" => 3},
        "3" => %{"price" => 4_000, "credit_cost" => 2},
        "4" => %{"price" => 3_000, "credit_cost" => 1}
      }
    })
    |> Repo.update!()

    {:ok, _} = Credits.grant_complimentary(nil, actor.household_id, %{amount: 3})
    assert {:ok, converted} = Bookings.convert_session_to_private(actor, session.id, 3)
    assert {:ok, booking} = Bookings.book(actor, player.id, converted.id, :credits)
    assert booking.credits_used == 2
  end

  test "private-session requests respect the configured maximum", ctx do
    actor = household_actor(ctx.tenant)

    assert {:ok, request} =
             Bookings.request_private_session(actor, ctx.offering.id, %{
               player_count: 4,
               preferred_times: [days_from_now(5)],
               notes: "Weekday evening"
             })

    assert request.status == :pending

    assert {:error, {:private_request_not_allowed, _message}} =
             Bookings.request_private_session(actor, ctx.offering.id, %{player_count: 5})
  end

  test "households see request status and every manager is emailed after review", ctx do
    actor = household_actor(ctx.tenant)
    second_manager = insert(:customer_user)
    insert(:household_member, household: actor.household, customer_user: second_manager)
    scheduled = session(ctx, days_from_now(6), 2)
    staff_user = insert(:staff_user)

    staff =
      StaffActor.new(
        staff_user_id: staff_user.id,
        tenant_id: ctx.tenant.id,
        role: :owner
      )

    assert {:ok, request} =
             Bookings.request_private_session(actor, ctx.offering.id, %{
               player_count: 4,
               preferred_times: [days_from_now(6)],
               notes: "After school"
             })

    assert [listed] = Bookings.list_private_session_requests(actor.household_id)
    assert listed.id == request.id
    assert listed.status == :pending

    assert {:ok, approved} =
             Bookings.review_private_session_request(staff, request.id, :approved, %{
               session_id: scheduled.id
             })

    assert approved.status == :approved
    assert approved.session_id == scheduled.id
    assert [listed] = Bookings.list_private_session_requests(actor.household_id)
    assert listed.status == :approved

    for email <- [actor.customer_user.email, second_manager.email] do
      %{data: deliveries} = Notifications.deliveries_for_emails([email])

      assert Enum.any?(
               deliveries,
               &(&1.message.template_key == "private_session_request_reviewed")
             )
    end
  end

  test "resending an invitation is capped", ctx do
    inviter = household_actor(ctx.tenant)
    inviter_player = player(inviter.household_id)
    session = session(ctx, days_from_now(4), 2)

    {:ok, _} = Credits.grant_complimentary(nil, inviter.household_id, %{amount: 2})
    assert {:ok, %Booking{}} = Bookings.book(inviter, inviter_player.id, session.id, :credits)

    assert {:ok, %{invitation: invitation}} =
             Bookings.invite(inviter, session.id, %{
               email: "friend@example.com",
               payment_mode: :split
             })

    for _ <- 1..3, do: assert({:ok, _} = Bookings.resend_invitation(inviter, invitation.id))

    assert {:error, {:too_many_resends, _message}} =
             Bookings.resend_invitation(inviter, invitation.id)
  end

  test "a household cannot hold unlimited pending invitations", ctx do
    inviter = household_actor(ctx.tenant)
    inviter_player = player(inviter.household_id)
    {:ok, _} = Credits.grant_complimentary(nil, inviter.household_id, %{amount: 20})

    results =
      for n <- 1..11 do
        session = session(ctx, days_from_now(4 + n), 2)
        assert {:ok, %Booking{}} = Bookings.book(inviter, inviter_player.id, session.id, :credits)

        Bookings.invite(inviter, session.id, %{
          email: "friend#{n}@example.com",
          payment_mode: :split
        })
      end

    assert Enum.count(results, &match?({:ok, _}, &1)) == 10
    assert {:error, {:too_many_invitations, _message}} = List.last(results)
  end

  defp household_actor(tenant) do
    household = insert(:household)
    user = insert(:customer_user)
    insert(:household_member, household: household, customer_user: user)

    CustomerActor.new(
      customer_user_id: user.id,
      household_id: household.id,
      tenant_id: tenant.id,
      customer_user: user,
      household: household
    )
  end

  defp player(household_id) do
    {:ok, player} =
      Players.create_player(nil, %{
        household_id: household_id,
        first_name: "Invite",
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

  defp session(ctx, starts_at, capacity) do
    session =
      insert(:session,
        offering_id: ctx.offering.id,
        venue_id: ctx.venue.id,
        capacity: capacity,
        starts_at: starts_at,
        ends_at: DateTime.add(starts_at, 1, :hour)
      )

    coach = insert(:membership, role: :coach)
    insert(:session_coach, session: session, membership_id: coach.id)
    session
  end

  defp days_from_now(days), do: DateTime.add(now(), days, :day)
  defp credit_balance(household_id), do: Credits.balance(household_id) |> Enum.sum_by(& &1.amount)
  defp now, do: DateTime.utc_now() |> DateTime.truncate(:microsecond)
end
