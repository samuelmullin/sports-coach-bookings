defmodule SportsCoachBookings.Notifications.Subscribers.EventSubscriberTest do
  use SportsCoachBookings.DataCase, async: false

  alias SportsCoachBookings.Events
  alias SportsCoachBookings.Events.EventWorker
  alias SportsCoachBookings.Notifications
  alias SportsCoachBookings.Notifications.Delivery
  alias SportsCoachBookings.Notifications.Message
  alias SportsCoachBookings.Notifications.Subscribers.EventSubscriber
  alias SportsCoachBookings.Notifications.Templates

  @event_templates %{
    "staff.joined" => "staff_joined",
    "staff.removed" => "staff_removed",
    "customer.registered" => "customer_welcome",
    "household.member_joined" => "household_member_joined",
    "waiver.published" => "waiver_resign_required",
    "waiver.signed" => "waiver_signed",
    "order.paid" => "order_receipt",
    "order.refunded" => "order_refunded",
    "order.expired" => "order_expired",
    "credits.granted" => "credits_granted",
    "credits.expiring_soon" => "credits_expiring",
    "credits.expired" => "credits_expired",
    "session.cancelled" => "session_cancelled_by_provider",
    "session.rescheduled" => "session_rescheduled",
    "booking.created" => "booking_confirmed",
    "booking.cancelled" => "booking_cancelled",
    "booking.rebooked" => "booking_rebooked",
    "booking.attended" => "booking_attended",
    "booking.no_show" => "booking_no_show",
    "feedback.submitted" => "feedback_shared",
    "stock.low" => "admin_low_stock"
  }

  setup do
    tenant = insert(:tenant, name: "Alpha Coaching")
    put_tenant(tenant)

    venue =
      insert(:venue, tenant_id: tenant.id, name: "Riverside Field", timezone: "America/Toronto")

    offering = insert(:offering, tenant_id: tenant.id, name: "U12 Skills")

    coach_user = insert(:staff_user, email: "coach@example.com")
    coach = insert(:membership, tenant_id: tenant.id, staff_user: coach_user, role: :coach)

    owner_user = insert(:staff_user, email: "owner@example.com")
    owner = insert(:membership, tenant_id: tenant.id, staff_user: owner_user, role: :owner)

    session =
      insert(:session,
        tenant_id: tenant.id,
        offering_id: offering.id,
        venue_id: venue.id,
        starts_at: ~U[2026-01-06 22:00:00.000000Z],
        ends_at: ~U[2026-01-06 23:00:00.000000Z]
      )

    insert(:session_coach, tenant_id: tenant.id, session: session, membership_id: coach.id)

    household = insert(:household, tenant_id: tenant.id)
    customer = insert(:customer_user, tenant_id: tenant.id, email: "manager@example.com")

    member =
      insert(:household_member,
        tenant_id: tenant.id,
        household: household,
        customer_user: customer,
        role: :manager
      )

    player =
      insert(:player,
        tenant_id: tenant.id,
        household_id: household.id,
        first_name: "Riley",
        last_name: "Rivera",
        preferred_name: "Riley"
      )

    %{
      tenant: tenant,
      venue: venue,
      offering: offering,
      session: session,
      coach: coach,
      coach_user: coach_user,
      owner: owner,
      owner_user: owner_user,
      household: household,
      customer: customer,
      member: member,
      player: player
    }
  end

  describe "wiring" do
    test "every wp-16 event is registered to this subscriber" do
      for {event, _template} <- @event_templates do
        assert EventSubscriber in Events.subscribers(event), "expected #{event} subscriber"
      end
    end

    test "auth/invite events are not double-handled by wp-16" do
      refute EventSubscriber in Events.subscribers("staff.invited")
      refute EventSubscriber in Events.subscribers("household.member_invited")
    end
  end

  describe "templates" do
    test "all wp-16 templates are registered and render for two tenants' branding" do
      tenant_a = insert(:tenant, name: "Alpha")
      tenant_b = insert(:tenant, name: "Bravo")

      put_tenant(tenant_a)
      insert(:branding, tenant_id: tenant_a.id, primary_color: "#ff0000")
      put_tenant(tenant_b)
      insert(:branding, tenant_id: tenant_b.id, primary_color: "#00ff00")

      for template <- Map.values(@event_templates) do
        assert {:ok, rendered_a} =
                 Notifications.render(template, sample_assigns(template), tenant_id: tenant_a.id)

        assert {:ok, rendered_b} =
                 Notifications.render(template, sample_assigns(template), tenant_id: tenant_b.id)

        assert rendered_a.html =~ "Alpha"
        assert rendered_a.html =~ "#ff0000"
        assert rendered_b.html =~ "Bravo"
        assert rendered_b.html =~ "#00ff00"
        assert is_binary(rendered_a.text)
      end
    end
  end

  describe "booking.created" do
    test "sends a confirmation with an .ics attachment for a confirmed booking", ctx do
      booking = confirmed_booking(ctx)

      assert :ok =
               EventSubscriber.handle_event("booking.created", %{
                 "booking_id" => booking.id,
                 "status" => "confirmed",
                 "session_id" => ctx.session.id,
                 "player_id" => ctx.player.id,
                 "household_id" => ctx.household.id,
                 "tenant_id" => ctx.tenant.id
               })

      message = one_message("booking_confirmed")
      assert deliveries(message) |> Enum.map(& &1.email) == [ctx.customer.email]
      assert message.assigns["player_name"] == "Riley"
      assert message.assigns["offering_name"] == "U12 Skills"
      assert message.assigns["venue_name"] == "Riverside Field"

      [job] = notifications_jobs()
      assert [attachment] = job.args["attachments"]
      assert attachment["filename"] == "booking.ics"

      ics = Base.decode64!(attachment["content_base64"])
      assert ics =~ "BEGIN:VCALENDAR"
      assert ics =~ "UID:#{booking.id}@sportscoachbookings.com"
      assert ics =~ "DTSTART;TZID=America/Toronto:"
    end

    test "does not email a held booking", ctx do
      booking = confirmed_booking(ctx, %{status: :held})

      assert :ok =
               EventSubscriber.handle_event("booking.created", %{
                 "booking_id" => booking.id,
                 "status" => "held",
                 "tenant_id" => ctx.tenant.id
               })

      assert Repo.aggregate(Message, :count) == 0
    end

    test "is idempotent when replayed", ctx do
      booking = confirmed_booking(ctx)

      payload = %{
        "booking_id" => booking.id,
        "status" => "confirmed",
        "tenant_id" => ctx.tenant.id
      }

      assert :ok = EventSubscriber.handle_event("booking.created", payload)
      assert :ok = EventSubscriber.handle_event("booking.created", payload)

      assert Repo.aggregate(Message, :count) == 1
      assert Repo.aggregate(Delivery, :count) == 1
    end

    test "a suppressed address is skipped", ctx do
      booking = confirmed_booking(ctx)
      insert(:suppression, tenant_id: ctx.tenant.id, email: ctx.customer.email, reason: :bounce)

      assert :ok =
               EventSubscriber.handle_event("booking.created", %{
                 "booking_id" => booking.id,
                 "status" => "confirmed",
                 "tenant_id" => ctx.tenant.id
               })

      message = one_message("booking_confirmed")
      assert [%{status: :suppressed}] = deliveries(message)
      assert notifications_jobs() == []
    end
  end

  describe "end-to-end publish" do
    test "publishing booking.created delivers exactly once, even on replay", ctx do
      booking = confirmed_booking(ctx)
      put_tenant(ctx.tenant)

      {:ok, _job} =
        Repo.with_tenant_tx(fn ->
          Events.publish("booking.created", %{
            booking_id: booking.id,
            status: "confirmed",
            tenant_id: ctx.tenant.id
          })
        end)

      job = Repo.one!(from j in Oban.Job, where: j.args["name"] == "booking.created")

      assert :ok = EventWorker.perform(job)
      # Replay the same outbox job: at-least-once delivery must not double-send.
      assert :ok = EventWorker.perform(job)

      assert Repo.aggregate(Message, :count) == 1
      assert Repo.aggregate(Delivery, :count) == 1
    end
  end

  describe "other events" do
    test "staff.joined and staff.removed notify owners/admins", ctx do
      base = %{
        "membership_id" => ctx.owner.id,
        "staff_user_id" => ctx.coach_user.id,
        "tenant_id" => ctx.tenant.id
      }

      assert :ok = EventSubscriber.handle_event("staff.joined", Map.put(base, "role", "coach"))

      assert one_message("staff_joined") |> deliveries() |> Enum.map(& &1.email) == [
               ctx.owner_user.email
             ]

      assert :ok = EventSubscriber.handle_event("staff.removed", Map.put(base, "role", "coach"))

      assert one_message("staff_removed") |> deliveries() |> Enum.map(& &1.email) == [
               ctx.owner_user.email
             ]
    end

    test "customer.registered welcomes the customer", ctx do
      assert :ok =
               EventSubscriber.handle_event("customer.registered", %{
                 "customer_user_id" => ctx.customer.id,
                 "household_id" => ctx.household.id,
                 "tenant_id" => ctx.tenant.id
               })

      message = one_message("customer_welcome")
      assert message.assigns["first_name"] == "Casey"
      assert deliveries(message) |> Enum.map(& &1.email) == [ctx.customer.email]
    end

    test "household.member_joined notifies existing managers", ctx do
      assert :ok =
               EventSubscriber.handle_event("household.member_joined", %{
                 "household_id" => ctx.household.id,
                 "customer_user_id" => ctx.customer.id,
                 "member_id" => ctx.member.id,
                 "tenant_id" => ctx.tenant.id
               })

      assert one_message("household_member_joined") |> deliveries() |> Enum.map(& &1.email) ==
               [ctx.customer.email]
    end

    test "waiver.published emails households that must re-sign", ctx do
      template =
        insert(:waiver_template,
          tenant_id: ctx.tenant.id,
          name: "Participation Waiver",
          require_resign_on_new_version: true
        )

      version =
        insert(:waiver_version,
          tenant_id: ctx.tenant.id,
          waiver_template: template,
          status: :published
        )

      assert :ok =
               EventSubscriber.handle_event("waiver.published", %{
                 "template_id" => template.id,
                 "version_id" => version.id,
                 "require_resign" => true,
                 "tenant_id" => ctx.tenant.id
               })

      message = one_message("waiver_resign_required")
      assert message.assigns["waiver_name"] == "Participation Waiver"
      assert deliveries(message) |> Enum.map(& &1.email) == [ctx.customer.email]
    end

    test "waiver.published without require_resign sends nothing", ctx do
      assert :ok =
               EventSubscriber.handle_event("waiver.published", %{
                 "template_id" => Ecto.UUID.generate(),
                 "version_id" => Ecto.UUID.generate(),
                 "require_resign" => false,
                 "tenant_id" => ctx.tenant.id
               })

      assert Repo.aggregate(Message, :count) == 0
    end

    test "waiver.signed confirms to the household", ctx do
      template = insert(:waiver_template, tenant_id: ctx.tenant.id, name: "Participation Waiver")

      version =
        insert(:waiver_version,
          tenant_id: ctx.tenant.id,
          waiver_template: template,
          status: :published
        )

      assert :ok =
               EventSubscriber.handle_event("waiver.signed", %{
                 "signature_id" => Ecto.UUID.generate(),
                 "player_id" => ctx.player.id,
                 "waiver_version_id" => version.id,
                 "template_id" => template.id,
                 "tenant_id" => ctx.tenant.id
               })

      assert one_message("waiver_signed") |> deliveries() |> Enum.map(& &1.email) ==
               [ctx.customer.email]
    end

    test "order.paid sends a receipt", ctx do
      order =
        insert(:order, tenant_id: ctx.tenant.id, household_id: ctx.household.id, status: :paid)

      insert(:order_line,
        tenant_id: ctx.tenant.id,
        order: order,
        type: :package,
        description: "U12 Package",
        line_total: 10_000
      )

      assert :ok =
               EventSubscriber.handle_event("order.paid", %{
                 "order_id" => order.id,
                 "household_id" => ctx.household.id,
                 "tenant_id" => ctx.tenant.id
               })

      message = one_message("order_receipt")
      assert message.assigns["order_number"] == order.number
      assert deliveries(message) |> Enum.map(& &1.email) == [ctx.customer.email]
    end

    test "order.refunded and order.expired", ctx do
      order =
        insert(:order,
          tenant_id: ctx.tenant.id,
          household_id: ctx.household.id,
          status: :paid,
          refunded_total: 2_500
        )

      assert :ok =
               EventSubscriber.handle_event("order.refunded", %{
                 "order_id" => order.id,
                 "tenant_id" => ctx.tenant.id
               })

      assert Repo.get_by!(Message, template_key: "order_refunded")

      pending = insert(:order, tenant_id: ctx.tenant.id, household_id: ctx.household.id)

      assert :ok =
               EventSubscriber.handle_event("order.expired", %{
                 "order_id" => pending.id,
                 "tenant_id" => ctx.tenant.id
               })

      assert Repo.get_by!(Message, template_key: "order_expired")
    end

    test "credits.granted, expiring_soon, and expired", ctx do
      lot =
        insert(:credit_lot,
          tenant_id: ctx.tenant.id,
          household_id: ctx.household.id,
          quantity_granted: 5,
          remaining: 5,
          expires_at: ~U[2026-03-01 00:00:00.000000Z]
        )

      assert :ok =
               EventSubscriber.handle_event("credits.granted", %{
                 "household_id" => ctx.household.id,
                 "lot_id" => lot.id,
                 "amount" => 5,
                 "tenant_id" => ctx.tenant.id
               })

      assert one_message("credits_granted") |> deliveries() |> Enum.map(& &1.email) ==
               [ctx.customer.email]

      assert :ok =
               EventSubscriber.handle_event("credits.expiring_soon", %{
                 "household_id" => ctx.household.id,
                 "lot_id" => lot.id,
                 "amount" => 3,
                 "expires_at" => "2026-03-01T00:00:00Z",
                 "tenant_id" => ctx.tenant.id
               })

      assert Repo.get_by!(Message, template_key: "credits_expiring")

      assert :ok =
               EventSubscriber.handle_event("credits.expired", %{
                 "household_id" => ctx.household.id,
                 "lot_id" => lot.id,
                 "amount" => 2,
                 "tenant_id" => ctx.tenant.id
               })

      assert Repo.get_by!(Message, template_key: "credits_expired")
    end

    test "session.cancelled notifies affected households and coaches", ctx do
      confirmed_booking(ctx)

      assert :ok =
               EventSubscriber.handle_event("session.cancelled", %{
                 "session_id" => ctx.session.id,
                 "reason" => "Field unavailable",
                 "starts_at" => "2026-01-06T22:00:00Z",
                 "tenant_id" => ctx.tenant.id
               })

      message = one_message("session_cancelled_by_provider")
      emails = message |> deliveries() |> Enum.map(& &1.email) |> Enum.sort()
      assert emails == Enum.sort([ctx.customer.email, ctx.coach_user.email])
    end

    test "session.rescheduled notifies affected households and coaches", ctx do
      confirmed_booking(ctx)

      assert :ok =
               EventSubscriber.handle_event("session.rescheduled", %{
                 "session_id" => ctx.session.id,
                 "previous_starts_at" => "2026-01-06T22:00:00Z",
                 "starts_at" => "2026-01-08T22:00:00Z",
                 "venue_id" => ctx.venue.id,
                 "tenant_id" => ctx.tenant.id
               })

      message = one_message("session_rescheduled")
      emails = message |> deliveries() |> Enum.map(& &1.email) |> Enum.sort()
      assert emails == Enum.sort([ctx.customer.email, ctx.coach_user.email])
    end

    test "booking.cancelled, rebooked, attended, no_show", ctx do
      booking = confirmed_booking(ctx)

      assert :ok =
               EventSubscriber.handle_event("booking.cancelled", %{
                 "booking_id" => booking.id,
                 "session_id" => ctx.session.id,
                 "player_id" => ctx.player.id,
                 "household_id" => ctx.household.id,
                 "credit_outcome" => "returned",
                 "tenant_id" => ctx.tenant.id
               })

      assert Repo.get_by!(Message, template_key: "booking_cancelled")

      from_booking =
        confirmed_booking(ctx, %{
          player_id: insert(:player, tenant_id: ctx.tenant.id, household_id: ctx.household.id).id
        })

      to_booking =
        confirmed_booking(ctx, %{
          player_id: insert(:player, tenant_id: ctx.tenant.id, household_id: ctx.household.id).id
        })

      assert :ok =
               EventSubscriber.handle_event("booking.rebooked", %{
                 "booking_id" => to_booking.id,
                 "from_booking_id" => from_booking.id,
                 "session_id" => ctx.session.id,
                 "source_session_id" => ctx.session.id,
                 "player_id" => ctx.player.id,
                 "household_id" => ctx.household.id,
                 "tenant_id" => ctx.tenant.id
               })

      assert Repo.get_by!(Message, template_key: "booking_rebooked")

      assert :ok =
               EventSubscriber.handle_event("booking.attended", %{
                 "booking_id" => booking.id,
                 "session_id" => ctx.session.id,
                 "player_id" => ctx.player.id,
                 "household_id" => ctx.household.id,
                 "tenant_id" => ctx.tenant.id
               })

      assert Repo.get_by!(Message, template_key: "booking_attended")

      assert :ok =
               EventSubscriber.handle_event("booking.no_show", %{
                 "booking_id" => booking.id,
                 "session_id" => ctx.session.id,
                 "player_id" => ctx.player.id,
                 "household_id" => ctx.household.id,
                 "tenant_id" => ctx.tenant.id
               })

      assert Repo.get_by!(Message, template_key: "booking_no_show")
    end

    test "feedback.submitted shares feedback with the household", ctx do
      feedback =
        insert(:session_feedback,
          tenant_id: ctx.tenant.id,
          session_id: ctx.session.id,
          player_id: ctx.player.id,
          coach_id: ctx.coach.id,
          body: "Strong session.",
          visibility: :shared,
          shared_at: DateTime.utc_now(),
          skill_ratings: %{"first_touch" => 4}
        )

      assert :ok =
               EventSubscriber.handle_event("feedback.submitted", %{
                 "feedback_id" => feedback.id,
                 "session_id" => ctx.session.id,
                 "player_id" => ctx.player.id,
                 "coach_id" => ctx.coach.id,
                 "household_id" => ctx.household.id,
                 "updated" => false,
                 "tenant_id" => ctx.tenant.id
               })

      message = one_message("feedback_shared")
      assert message.assigns["body"] == "Strong session."
      assert deliveries(message) |> Enum.map(& &1.email) == [ctx.customer.email]
    end

    test "stock.low notifies owners/admins", ctx do
      product = insert(:product, tenant_id: ctx.tenant.id, name: "Training Jersey")

      variant =
        insert(:product_variant,
          tenant_id: ctx.tenant.id,
          product: product,
          low_stock_threshold: 2
        )

      assert :ok =
               EventSubscriber.handle_event("stock.low", %{
                 "variant_id" => variant.id,
                 "product_id" => product.id,
                 "available" => 1,
                 "threshold" => 2,
                 "tenant_id" => ctx.tenant.id
               })

      message = one_message("admin_low_stock")
      assert message.assigns["product_name"] == "Training Jersey"
      assert deliveries(message) |> Enum.map(& &1.email) == [ctx.owner_user.email]
    end
  end

  ## Helpers

  defp confirmed_booking(ctx, attrs \\ %{}) do
    insert(
      :booking,
      Map.merge(
        %{
          tenant_id: ctx.tenant.id,
          session_id: ctx.session.id,
          player_id: ctx.player.id,
          household_id: ctx.household.id,
          status: :confirmed
        },
        attrs
      )
    )
  end

  defp one_message(template) do
    Repo.get_by!(Message, template_key: template)
  end

  defp deliveries(message) do
    Repo.all(from d in Delivery, where: d.message_id == ^message.id)
  end

  defp notifications_jobs do
    Repo.all(from j in Oban.Job, where: j.queue == "notifications")
  end

  defp sample_assigns(template) do
    Templates.sample_assigns(template)
  end
end
