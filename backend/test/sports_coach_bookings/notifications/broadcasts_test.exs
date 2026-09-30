defmodule SportsCoachBookings.Notifications.BroadcastsTest do
  use SportsCoachBookings.DataCase, async: false

  import Ecto.Query

  alias SportsCoachBookings.Core.StaffActor
  alias SportsCoachBookings.Notifications
  alias SportsCoachBookings.Notifications.Broadcasts
  alias SportsCoachBookings.Notifications.Broadcasts.Broadcast
  alias SportsCoachBookings.Notifications.Broadcasts.BroadcastRecipient
  alias SportsCoachBookings.Notifications.Broadcasts.Segments
  alias SportsCoachBookings.Notifications.Message
  alias SportsCoachBookings.ObanHelpers

  setup do
    tenant = insert(:tenant)
    put_tenant(tenant)
    %{tenant: tenant}
  end

  defp actor(tenant) do
    StaffActor.new(staff_user_id: Ecto.UUID.generate(), tenant_id: tenant.id, role: :owner)
  end

  defp household_with_manager(tenant, email, opts \\ []) do
    household = insert(:household, tenant_id: tenant.id)
    customer = insert(:customer_user, tenant_id: tenant.id, email: email)
    insert(:household_member, tenant_id: tenant.id, household: household, customer_user: customer)

    if opts[:marketing_opt_in] do
      {:ok, _} =
        Notifications.Preferences.update({:customer_user, customer.id}, %{marketing_opt_in: true})
    end

    %{household: household, customer: customer, email: email}
  end

  defp create_session(tenant, opts \\ []) do
    offering = insert(:offering, tenant_id: tenant.id)
    venue_id = Keyword.get(opts, :venue_id, Ecto.UUID.generate())
    starts_at = DateTime.add(DateTime.utc_now(), 3, :day) |> DateTime.truncate(:microsecond)

    session =
      insert(:session,
        tenant_id: tenant.id,
        offering_id: offering.id,
        venue_id: venue_id,
        starts_at: starts_at,
        ends_at: DateTime.add(starts_at, 3600, :second),
        status: :scheduled
      )

    %{offering: offering, session: session, venue_id: venue_id}
  end

  defp book(tenant, household, session, dob \\ ~D[2015-05-01]) do
    player =
      insert(:player, tenant_id: tenant.id, household_id: household.id, date_of_birth: dob)

    insert(:booking,
      tenant_id: tenant.id,
      session_id: session.id,
      player_id: player.id,
      household_id: household.id,
      status: :confirmed
    )

    player
  end

  defp broadcast_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        "subject" => "Hello",
        "body_markdown" => "# Hello\n\nSome news.",
        "category" => "marketing",
        "segment" => %{"match" => "all", "conditions" => []}
      },
      overrides
    )
  end

  defp bookings_condition(session_id) do
    %{"type" => "bookings", "session_ids" => [session_id]}
  end

  defp drain_notifications do
    case ObanHelpers.drain(:notifications) do
      0 -> :ok
      _ -> drain_notifications()
    end
  end

  describe "segment resolution" do
    test "all households matches every household", %{tenant: tenant} do
      h1 = household_with_manager(tenant, "a@example.com")
      h2 = household_with_manager(tenant, "b@example.com")

      ids = Segments.household_ids(%{"match" => "all", "conditions" => []})

      assert MapSet.member?(ids, h1.household.id)
      assert MapSet.member?(ids, h2.household.id)
    end

    test "bookings by session / offering / venue / date range", %{tenant: tenant} do
      data = create_session(tenant)
      included = household_with_manager(tenant, "in@example.com")
      excluded = household_with_manager(tenant, "out@example.com")
      book(tenant, included.household, data.session)

      for condition <- [
            %{"type" => "bookings", "session_ids" => [data.session.id]},
            %{"type" => "bookings", "offering_ids" => [data.offering.id]},
            %{"type" => "bookings", "venue_id" => data.venue_id},
            %{
              "type" => "bookings",
              "from" => DateTime.to_iso8601(DateTime.add(DateTime.utc_now(), -1, :day)),
              "to" => DateTime.to_iso8601(DateTime.add(DateTime.utc_now(), 30, :day))
            }
          ] do
        ids = Segments.household_ids(%{"match" => "all", "conditions" => [condition]})
        assert MapSet.member?(ids, included.household.id), "expected #{inspect(condition)}"
        refute MapSet.member?(ids, excluded.household.id)
      end
    end

    test "bookings status defaults to confirmed", %{tenant: tenant} do
      data = create_session(tenant)
      household = household_with_manager(tenant, "held@example.com")

      player = insert(:player, tenant_id: tenant.id, household_id: household.household.id)

      insert(:booking,
        tenant_id: tenant.id,
        session_id: data.session.id,
        player_id: player.id,
        household_id: household.household.id,
        status: :held
      )

      ids =
        Segments.household_ids(%{
          "match" => "all",
          "conditions" => [bookings_condition(data.session.id)]
        })

      refute MapSet.member?(ids, household.household.id)
    end

    test "player age range", %{tenant: tenant} do
      young = household_with_manager(tenant, "young@example.com")
      older = household_with_manager(tenant, "older@example.com")

      insert(:player,
        tenant_id: tenant.id,
        household_id: young.household.id,
        date_of_birth: ~D[2020-01-01]
      )

      insert(:player,
        tenant_id: tenant.id,
        household_id: older.household.id,
        date_of_birth: ~D[2010-01-01]
      )

      ids =
        Segments.household_ids(%{
          "match" => "all",
          "conditions" => [%{"type" => "player_age", "min" => 13, "max" => 18}]
        })

      assert MapSet.member?(ids, older.household.id)
      refute MapSet.member?(ids, young.household.id)
    end

    test "credits balance and expiry", %{tenant: tenant} do
      with_balance = household_with_manager(tenant, "balance@example.com")
      empty = household_with_manager(tenant, "empty@example.com")

      insert(:credit_lot,
        tenant_id: tenant.id,
        household_id: with_balance.household.id,
        remaining: 3
      )

      insert(:credit_lot, tenant_id: tenant.id, household_id: empty.household.id, remaining: 0)

      ids = Segments.household_ids(%{"type" => "credits", "min_balance" => 1})
      assert MapSet.member?(ids, with_balance.household.id)
      refute MapSet.member?(ids, empty.household.id)

      expiring = household_with_manager(tenant, "expiring@example.com")

      insert(:credit_lot,
        tenant_id: tenant.id,
        household_id: expiring.household.id,
        remaining: 1,
        expires_at: DateTime.add(DateTime.utc_now(), 2, :day) |> DateTime.truncate(:microsecond)
      )

      soon =
        Segments.household_ids(%{
          "type" => "credits",
          "expiring_before" => DateTime.to_iso8601(DateTime.add(DateTime.utc_now(), 7, :day))
        })

      assert MapSet.member?(soon, expiring.household.id)
      refute MapSet.member?(soon, with_balance.household.id)
    end

    test "package purchase", %{tenant: tenant} do
      bought = household_with_manager(tenant, "bought@example.com")
      other = household_with_manager(tenant, "other@example.com")
      package_id = Ecto.UUID.generate()

      order =
        insert(:order, tenant_id: tenant.id, household_id: bought.household.id, status: :paid)

      insert(:order_line,
        tenant_id: tenant.id,
        order: order,
        type: :package,
        ref_id: package_id
      )

      ids = Segments.household_ids(%{"type" => "package", "package_id" => package_id})

      assert MapSet.member?(ids, bought.household.id)
      refute MapSet.member?(ids, other.household.id)
    end

    test "conditions combine with AND", %{tenant: tenant} do
      data = create_session(tenant)
      match = household_with_manager(tenant, "match@example.com")
      wrong_age = household_with_manager(tenant, "wrongage@example.com")
      book(tenant, match.household, data.session, ~D[2015-01-01])
      book(tenant, wrong_age.household, data.session, ~D[2000-01-01])

      ids =
        Segments.household_ids(%{
          "match" => "all",
          "conditions" => [
            bookings_condition(data.session.id),
            %{"type" => "player_age", "min" => 8, "max" => 14}
          ]
        })

      assert MapSet.member?(ids, match.household.id)
      refute MapSet.member?(ids, wrong_age.household.id)
    end
  end

  describe "marketing vs operational recipients" do
    test "marketing excludes non-opted-in and suppressed addresses", %{tenant: tenant} do
      data = create_session(tenant)
      opted_in = household_with_manager(tenant, "optin@example.com", marketing_opt_in: true)
      not_opted_in = household_with_manager(tenant, "noopt@example.com")
      suppressed = household_with_manager(tenant, "bounce@example.com", marketing_opt_in: true)

      for h <- [opted_in, not_opted_in, suppressed], do: book(tenant, h.household, data.session)
      {:ok, _} = Notifications.Suppressions.suppress(tenant.id, "bounce@example.com", :bounce)

      segment = %{"match" => "all", "conditions" => [bookings_condition(data.session.id)]}

      marketing = Segments.recipients(segment, :marketing) |> Enum.map(& &1.email)
      assert marketing == ["optin@example.com"]

      operational = Segments.recipients(segment, :operational) |> Enum.map(& &1.email)

      assert Enum.sort(operational) == [
               "bounce@example.com",
               "noopt@example.com",
               "optin@example.com"
             ]
    end
  end

  describe "create and validation" do
    test "operational broadcasts require a booking-based segment", %{tenant: tenant} do
      attrs = broadcast_attrs(%{"category" => "operational"})

      assert {:error, changeset} = Broadcasts.create_broadcast(actor(tenant), attrs)
      assert %{segment: [_ | _]} = errors_on(changeset)

      data = create_session(tenant)

      attrs =
        broadcast_attrs(%{
          "category" => "operational",
          "segment" => %{"match" => "all", "conditions" => [bookings_condition(data.session.id)]}
        })

      assert {:ok, %Broadcast{status: :draft, category: :operational}} =
               Broadcasts.create_broadcast(actor(tenant), attrs)
    end

    test "an invalid segment is rejected", %{tenant: tenant} do
      attrs = broadcast_attrs(%{"segment" => %{"type" => "nope"}})

      assert {:error, changeset} = Broadcasts.create_broadcast(actor(tenant), attrs)
      assert %{segment: [_ | _]} = errors_on(changeset)
    end
  end

  describe "send and idempotency" do
    test "sends to the marketing segment once, and a re-run does not double-send", %{
      tenant: tenant
    } do
      data = create_session(tenant)
      opted_in = household_with_manager(tenant, "optin@example.com", marketing_opt_in: true)
      not_opted_in = household_with_manager(tenant, "noopt@example.com")
      book(tenant, opted_in.household, data.session)
      book(tenant, not_opted_in.household, data.session)

      attrs =
        broadcast_attrs(%{
          "segment" => %{"match" => "all", "conditions" => [bookings_condition(data.session.id)]}
        })

      {:ok, broadcast} = Broadcasts.create_broadcast(actor(tenant), attrs)
      assert {:ok, %{recipient_count: 1}} = Broadcasts.recipient_count(broadcast.id)

      {:ok, sending} = Broadcasts.send_now(actor(tenant), broadcast.id)
      assert sending.status == :sending

      drain_notifications()

      sent = Repo.get!(Broadcast, broadcast.id)
      assert sent.status == :sent
      assert sent.sent_at
      assert sent.recipient_count == 1

      [recipient] = Repo.all(BroadcastRecipient)
      assert recipient.email == "optin@example.com"
      assert recipient.status == :sent

      message_count = broadcast_message_count()
      assert message_count == 1

      # Re-run the send: no new messages, no new recipients.
      {:ok, _} = Broadcasts.send_now(actor(tenant), broadcast.id)
      drain_notifications()

      assert broadcast_message_count() == message_count
      assert Repo.aggregate(BroadcastRecipient, :count) == 1
      assert Repo.get!(Broadcast, broadcast.id).status == :sent
    end

    test "resuming a partially processed send never re-sends a delivered recipient", %{
      tenant: tenant
    } do
      data = create_session(tenant)
      h = household_with_manager(tenant, "resume@example.com", marketing_opt_in: true)
      book(tenant, h.household, data.session)

      attrs =
        broadcast_attrs(%{
          "segment" => %{"match" => "all", "conditions" => [bookings_condition(data.session.id)]}
        })

      {:ok, broadcast} = Broadcasts.create_broadcast(actor(tenant), attrs)
      {:ok, _} = Broadcasts.send_now(actor(tenant), broadcast.id)
      drain_notifications()

      message_count = broadcast_message_count()

      # Simulate a recipient that was not processed (still pending) by the restart.
      Repo.update_all(BroadcastRecipient,
        set: [status: :pending, delivery_id: nil, message_id: nil]
      )

      {:ok, _} = Broadcasts.start_send(broadcast.id)
      drain_notifications()

      # The engine's per-recipient idempotency key means no second message is created.
      assert broadcast_message_count() == message_count
    end

    test "operational broadcast reaches the whole booking segment", %{tenant: tenant} do
      data = create_session(tenant)
      opted_in = household_with_manager(tenant, "optin@example.com", marketing_opt_in: true)
      not_opted_in = household_with_manager(tenant, "noopt@example.com")
      book(tenant, opted_in.household, data.session)
      book(tenant, not_opted_in.household, data.session)

      attrs =
        broadcast_attrs(%{
          "category" => "operational",
          "segment" => %{"match" => "all", "conditions" => [bookings_condition(data.session.id)]}
        })

      {:ok, broadcast} = Broadcasts.create_broadcast(actor(tenant), attrs)
      {:ok, _} = Broadcasts.send_now(actor(tenant), broadcast.id)
      drain_notifications()

      assert Repo.get!(Broadcast, broadcast.id).recipient_count == 2
      assert Repo.aggregate(BroadcastRecipient, :count) == 2
    end
  end

  describe "schedule, cancel, and history" do
    test "scheduling enqueues a due-time job and cancelling wins", %{tenant: tenant} do
      {:ok, broadcast} = Broadcasts.create_broadcast(actor(tenant), broadcast_attrs())
      at = DateTime.add(DateTime.utc_now(), 3600, :second)

      {:ok, scheduled} = Broadcasts.schedule(actor(tenant), broadcast.id, at)
      assert scheduled.status == :scheduled
      assert DateTime.compare(scheduled.scheduled_for, at) == :eq

      assert {:ok, :not_due} = Broadcasts.start_send(broadcast.id, require_due: true)

      {:ok, cancelled} = Broadcasts.cancel(actor(tenant), broadcast.id)
      assert cancelled.status == :cancelled
      assert {:error, :cancelled} = Broadcasts.start_send(broadcast.id, require_due: true)
    end

    test "a due scheduled broadcast sends, and replaying the schedule worker is idempotent", %{
      tenant: tenant
    } do
      data = create_session(tenant)
      h = household_with_manager(tenant, "sched@example.com", marketing_opt_in: true)
      book(tenant, h.household, data.session)

      attrs =
        broadcast_attrs(%{
          "segment" => %{"match" => "all", "conditions" => [bookings_condition(data.session.id)]}
        })

      {:ok, broadcast} = Broadcasts.create_broadcast(actor(tenant), attrs)

      {:ok, _} =
        Broadcasts.schedule(
          actor(tenant),
          broadcast.id,
          DateTime.add(DateTime.utc_now(), 60, :second)
        )

      due = DateTime.add(DateTime.utc_now(), -60, :second) |> DateTime.truncate(:microsecond)
      broadcast = Repo.get!(Broadcast, broadcast.id)
      {:ok, _} = broadcast |> Broadcast.status_changeset(%{scheduled_for: due}) |> Repo.update()

      assert {:ok, _} = Broadcasts.start_send(broadcast.id, require_due: true)
      drain_notifications()
      assert broadcast_message_count() == 1

      assert {:ok, _} = Broadcasts.start_send(broadcast.id, require_due: true)
      drain_notifications()
      assert broadcast_message_count() == 1
    end

    test "history reports live delivery statuses", %{tenant: tenant} do
      data = create_session(tenant)
      h = household_with_manager(tenant, "history@example.com", marketing_opt_in: true)
      book(tenant, h.household, data.session)

      attrs =
        broadcast_attrs(%{
          "segment" => %{"match" => "all", "conditions" => [bookings_condition(data.session.id)]}
        })

      {:ok, broadcast} = Broadcasts.create_broadcast(actor(tenant), attrs)
      {:ok, _} = Broadcasts.send_now(actor(tenant), broadcast.id)
      drain_notifications()

      [recipient] = Repo.all(BroadcastRecipient)
      delivery = Repo.get!(SportsCoachBookings.Notifications.Delivery, recipient.delivery_id)

      delivery
      |> Ecto.Changeset.change(status: :delivered, delivered_at: DateTime.utc_now())
      |> Repo.update!()

      {:ok, history} = Broadcasts.history(broadcast.id)

      assert [%{delivery_status: :delivered}] = history.data
      assert history.stats["delivered"] == 1
      assert history.stats["total"] == 1
    end
  end

  describe "preview and test send" do
    test "preview renders the body and lists recipients", %{tenant: tenant} do
      data = create_session(tenant)
      h = household_with_manager(tenant, "preview@example.com", marketing_opt_in: true)
      book(tenant, h.household, data.session)

      attrs =
        broadcast_attrs(%{
          "segment" => %{"match" => "all", "conditions" => [bookings_condition(data.session.id)]}
        })

      {:ok, broadcast} = Broadcasts.create_broadcast(actor(tenant), attrs)
      {:ok, preview} = Broadcasts.preview(broadcast.id)

      assert preview.recipient_count == 1
      assert preview.recipients == ["preview@example.com"]
      assert preview.html =~ "<h1>Hello</h1>"
    end

    test "send test delivers to an address", %{tenant: tenant} do
      {:ok, broadcast} = Broadcasts.create_broadcast(actor(tenant), broadcast_attrs())

      assert {:ok, %{email: "test@example.com"}} =
               Broadcasts.send_test(actor(tenant), broadcast.id, "test@example.com")
    end
  end

  defp broadcast_message_count do
    Repo.aggregate(from(m in Message, where: m.template_key == "broadcast"), :count)
  end
end
