defmodule SportsCoachBookings.E2E.CancellationRebookJourneyTest do
  @moduledoc """
  WP-18 end-to-end: cancellation outcomes (return / forfeit / provider cancel),
  the snapshot invariant, and rebooking limits — all through the HTTP API.
  """
  use SportsCoachBookingsWeb.ConnCase, async: false

  import Ecto.Query
  import SportsCoachBookings.E2EHelpers

  alias Phoenix.ConnTest
  alias SportsCoachBookings.Bookings
  alias SportsCoachBookings.Commerce
  alias SportsCoachBookings.Credits
  alias SportsCoachBookings.Customers
  alias SportsCoachBookings.DataCase
  alias SportsCoachBookings.Payments
  alias SportsCoachBookings.Repo
  alias SportsCoachBookings.Scheduling.Session

  @customer_email "dana@cancel.test"

  setup do
    %{tenant: tenant, slug: slug, owner: owner} =
      onboard_tenant(build_conn(), %{
        name: "Cancel Co",
        slug: "cancel-#{System.unique_integer([:positive])}",
        email: "owner@cancel.test"
      })

    venue =
      owner
      |> json_post("/api/staff/catalog/venues", %{"name" => "Field"})
      |> json_response(201)

    offering =
      owner
      |> json_post("/api/staff/catalog/offerings", %{
        "name" => "Skills",
        "format" => "group",
        "duration_minutes" => 60,
        "default_capacity" => 8,
        "credit_cost" => 1
      })
      |> json_response(201)

    %{tenant: tenant, slug: slug, owner: owner, venue: venue, offering: offering}
  end

  test "returns credits outside the window and forfeits inside it", ctx do
    %{tenant: tenant, slug: slug, owner: owner, venue: venue, offering: offering} = ctx

    session = create_session(owner, offering["id"], venue["id"], 3)
    {customer, household_id, player_id} = customer_with_player(slug, tenant)

    DataCase.put_tenant(tenant)
    {:ok, _} = Credits.grant_complimentary(nil, household_id, %{amount: 5})

    # Outside the 24h window: a full credit return.
    booking = book(customer, player_id, session["id"])

    preview =
      customer
      |> get("/api/portal/bookings/#{booking["id"]}/cancel-preview")
      |> json_response(200)

    assert preview["outcome"]["credit_outcome"] == "return"

    cancelled =
      customer
      |> json_post("/api/portal/bookings/#{booking["id"]}/cancel", %{"reason" => "plans"})
      |> json_response(200)

    assert cancelled["cancel_outcome"]["credit_outcome"] == "return"
    assert cancelled["status"] == "cancelled"

    DataCase.put_tenant(tenant)
    assert Credits.balance(household_id) |> Enum.sum_by(& &1.amount) == 5
    assert {:ok, 5} = Credits.reconcile(household_id)

    # Inside the window: the credit is forfeited.
    second = book(customer, player_id, session["id"])

    shift_session_into_hours(session["id"], 2)
    DataCase.put_tenant(tenant)

    late_preview =
      customer
      |> get("/api/portal/bookings/#{second["id"]}/cancel-preview")
      |> json_response(200)

    assert late_preview["outcome"]["credit_outcome"] == "forfeit"

    late =
      customer
      |> json_post("/api/portal/bookings/#{second["id"]}/cancel", %{"reason" => "sick"})
      |> json_response(200)

    assert late["cancel_outcome"]["credit_outcome"] == "forfeit"

    DataCase.put_tenant(tenant)
    # 5 granted - 1 forfeited debit = 4; the lot still reconciles.
    assert Credits.balance(household_id) |> Enum.sum_by(& &1.amount) == 4
    assert {:ok, 4} = Credits.reconcile(household_id)
  end

  test "invariant 5: the outcome comes from the booking snapshot, not the live policy", ctx do
    %{tenant: tenant, slug: slug, owner: owner, venue: venue, offering: offering} = ctx

    session = create_session(owner, offering["id"], venue["id"], 3)
    {customer, household_id, player_id} = customer_with_player(slug, tenant)

    DataCase.put_tenant(tenant)
    {:ok, _} = Credits.grant_complimentary(nil, household_id, %{amount: 3})

    # Booked under the seeded default policy, which returns credits >= 24h out.
    booking = book(customer, player_id, session["id"])

    # Reassign the offering to a stricter policy that always forfeits.
    strict =
      owner
      |> json_post("/api/staff/policies", %{
        "name" => "Strict",
        "rules" => %{
          "cancellation_tiers" => [
            %{"min_hours_before" => 0, "credit_outcome" => "forfeit", "money_refund_pct" => 0}
          ],
          "no_show" => %{"credit_outcome" => "forfeit", "money_refund_pct" => 0},
          "late_cancel_counts_as_no_show" => false,
          "rebook" => %{
            "allowed" => true,
            "min_hours_before" => 12,
            "max_rebooks_per_booking" => 2,
            "same_offering_only" => true
          },
          "provider_cancelled" => %{"credit_outcome" => "return", "money_refund_pct" => 100}
        }
      })
      |> json_response(201)

    owner
    |> json_post("/api/staff/policies/#{strict["id"]}/assign", %{
      "offering_ids" => [offering["id"]]
    })
    |> json_response(200)

    # The booking's snapshot still wins: 72h out is a return under the old policy.
    preview =
      customer
      |> get("/api/portal/bookings/#{booking["id"]}/cancel-preview")
      |> json_response(200)

    assert preview["outcome"]["credit_outcome"] == "return"

    cancelled =
      customer
      |> json_post("/api/portal/bookings/#{booking["id"]}/cancel", %{"reason" => "change"})
      |> json_response(200)

    assert cancelled["cancel_outcome"]["credit_outcome"] == "return"

    DataCase.put_tenant(tenant)
    assert Credits.balance(household_id) |> Enum.sum_by(& &1.amount) == 3
    assert {:ok, 3} = Credits.reconcile(household_id)
  end

  test "provider cancellation refunds every booking and emails the household", ctx do
    %{tenant: tenant, slug: slug, owner: owner, venue: venue, offering: offering} = ctx

    session = create_session(owner, offering["id"], venue["id"], 3)
    {customer, household_id, player_id} = customer_with_player(slug, tenant)

    DataCase.put_tenant(tenant)
    {:ok, _} = Credits.grant_complimentary(nil, household_id, %{amount: 5})

    booking = book(customer, player_id, session["id"])
    drain_outbox()

    # Staff cancels the session; the subscriber cancels the booking with the
    # provider-cancel outcome (credits returned).
    assert %{"session" => %{"status" => "cancelled"}} =
             owner
             |> json_post("/api/staff/schedule/sessions/#{session["id"]}/cancel", %{
               "reason" => "snow"
             })
             |> json_response(200)

    drain_outbox()
    DataCase.put_tenant(tenant)

    stored = Bookings.get_booking!(booking["id"])
    assert stored.status == :cancelled
    assert stored.cancel_outcome["credit_outcome"] == "return"

    assert Credits.balance(household_id) |> Enum.sum_by(& &1.amount) == 5
    assert {:ok, 5} = Credits.reconcile(household_id)

    assert delivery_count(@customer_email, "booking_cancelled") == 1
  end

  test "rebooking carries the credits and is blocked beyond max_rebooks", ctx do
    %{tenant: tenant, slug: slug, owner: owner, venue: venue, offering: offering} = ctx

    s1 = create_session(owner, offering["id"], venue["id"], 3)
    s2 = create_session(owner, offering["id"], venue["id"], 4)
    s3 = create_session(owner, offering["id"], venue["id"], 5)
    s4 = create_session(owner, offering["id"], venue["id"], 6)

    {customer, household_id, player_id} = customer_with_player(slug, tenant)

    DataCase.put_tenant(tenant)
    {:ok, _} = Credits.grant_complimentary(nil, household_id, %{amount: 5})

    first = book(customer, player_id, s1["id"])

    second = rebook(customer, first["id"], s2["id"])
    assert second["rebooked_from_id"] == first["id"]
    assert second["rebook_count"] == 1

    third = rebook(customer, second["id"], s3["id"])
    assert third["rebook_count"] == 2

    # The third rebook exceeds max_rebooks_per_booking (2).
    blocked =
      customer
      |> json_post("/api/portal/bookings/#{third["id"]}/rebook", %{
        "target_session_id" => s4["id"]
      })

    assert json_response(blocked, 422)["error"]["code"] == "rebook_not_allowed"

    drain_outbox()
    DataCase.put_tenant(tenant)

    # One credit is still consumed; the append-only ledger reconciles.
    assert Credits.balance(household_id) |> Enum.sum_by(& &1.amount) == 4
    assert {:ok, 4} = Credits.reconcile(household_id)

    assert Repo.get!(Session, s1["id"]).booked_count == 0
    assert Repo.get!(Session, s3["id"]).booked_count == 1
    assert Repo.get!(Session, s4["id"]).booked_count == 0
  end

  test "a paid drop-in can be partially refunded on cancellation", ctx do
    %{tenant: tenant, slug: slug, owner: owner, venue: venue} = ctx

    # Connect the Fake provider so the drop-in can be checked out.
    owner |> post("/api/staff/payments/connect/onboarding") |> json_response(200)
    owner |> get("/api/staff/payments/connect") |> json_response(200)

    # A pay-per-session offering has a drop-in price.
    offering =
      owner
      |> json_post("/api/staff/catalog/offerings", %{
        "name" => "Drop-in",
        "format" => "group",
        "duration_minutes" => 60,
        "default_capacity" => 8,
        "credit_cost" => 1,
        "drop_in_price" => 3_000
      })
      |> json_response(201)

    session = create_session(owner, offering["id"], venue["id"], 3)
    {customer, _household_id, player_id} = customer_with_player(slug, tenant)

    # Book a pay-per-session hold, buy it through checkout, and confirm it.
    assert %{"status" => "held", "id" => hold_id} =
             customer
             |> json_post("/api/portal/bookings", %{
               "player_id" => player_id,
               "session_id" => session["id"],
               "method" => "paid"
             })
             |> json_response(201)

    customer
    |> json_post("/api/portal/cart/lines", %{
      "line" => %{"type" => "drop_in", "ref_id" => hold_id}
    })
    |> json_response(201)

    checkout = customer |> post("/api/portal/checkout") |> json_response(201)
    order_id = checkout["order"]["id"]
    assert checkout["order"]["total"] == 3_000

    assert json_response(complete_checkout(build_conn(), tenant, order_id, 3_000), 200)
    drain_outbox()
    DataCase.put_tenant(tenant)

    confirmed = Bookings.get_booking!(hold_id)
    assert confirmed.status == :confirmed
    assert confirmed.order_line_id

    # Staff grants a 50% partial refund on cancellation.
    cancelled =
      owner
      |> json_post("/api/staff/bookings/#{hold_id}/cancel", %{
        "outcome" => "partial_refund",
        "refund_pct" => 50,
        "reason" => "session ran short"
      })
      |> json_response(200)

    assert cancelled["cancel_outcome"]["credit_outcome"] == "forfeit"
    assert cancelled["cancel_outcome"]["refund_amount"] == 1_500
    assert cancelled["cancel_outcome"]["currency"] == "CAD"

    # The refund is reconciled onto the order by the `payment.refunded` event.
    drain_outbox()
    DataCase.put_tenant(tenant)

    order = Commerce.get_order!(order_id)
    assert order.refunded_total == 1_500
    assert Enum.sum_by(order.lines, & &1.refunded_amount) == 1_500

    payment = Payments.get_payment(order.payment_id)
    assert [%{amount: 1_500}] = Payments.list_refunds(payment.id)
  end

  ## Helpers

  defp create_session(owner, offering_id, venue_id, days) do
    starts_at = DateTime.utc_now() |> DateTime.add(days, :day) |> DateTime.truncate(:microsecond)

    owner
    |> json_post("/api/staff/schedule/sessions", %{
      "offering_id" => offering_id,
      "venue_id" => venue_id,
      "starts_at" => DateTime.to_iso8601(starts_at)
    })
    |> json_response(201)
    |> Map.fetch!("session")
  end

  defp customer_with_player(slug, tenant) do
    reg_conn = register_customer(build_conn(), slug, @customer_email)
    assert %{"household" => %{"id" => household_id}} = json_response(reg_conn, 201)

    DataCase.put_tenant(tenant)
    user = Customers.get_customer_user_by_email(@customer_email)
    token = Customers.create_confirm_token(user)
    build_conn() |> host(slug) |> json_post("/api/portal/confirmation", %{token: token})

    customer = ConnTest.recycle(reg_conn)

    player =
      customer
      |> json_post("/api/portal/players", %{
        "player" => %{
          "first_name" => "Jamie",
          "last_name" => "Reyes",
          "date_of_birth" => "2016-04-01"
        }
      })
      |> json_response(201)

    customer
    |> json_post("/api/portal/players/#{player["id"]}/emergency_contacts", %{
      "emergency_contact" => %{"name" => "Dana", "phone" => "+19025550111", "priority" => 1}
    })
    |> json_response(201)

    {customer, household_id, player["id"]}
  end

  defp book(customer, player_id, session_id) do
    customer
    |> json_post("/api/portal/bookings", %{
      "player_id" => player_id,
      "session_id" => session_id,
      "method" => "credits"
    })
    |> json_response(201)
  end

  defp rebook(customer, booking_id, target_session_id) do
    customer
    |> json_post("/api/portal/bookings/#{booking_id}/rebook", %{
      "target_session_id" => target_session_id
    })
    |> json_response(201)
  end

  defp shift_session_into_hours(session_id, hours) do
    starts_at =
      DateTime.utc_now() |> DateTime.add(hours, :hour) |> DateTime.truncate(:microsecond)

    Repo.update_all(
      from(s in Session, where: s.id == ^session_id),
      set: [starts_at: starts_at, ends_at: DateTime.add(starts_at, 3600, :second)]
    )
  end
end
