defmodule SportsCoachBookings.E2E.OnboardingPurchaseJourneyTest do
  @moduledoc """
  WP-18 end-to-end journey: tenant onboarding → catalog/schedule → customer
  registration + waiver → package purchase via the Fake provider + Stripe
  webhook → credits → booking → attendance → feedback → queued email.

  Everything is driven through the HTTP API (`ConnCase`) so the auth plugs,
  tenant resolution, JSON envelopes, policy checks, and transactional outbox all
  participate exactly as in production.
  """
  use SportsCoachBookingsWeb.ConnCase, async: false

  import Ecto.Query
  import SportsCoachBookings.E2EHelpers

  alias Phoenix.ConnTest
  alias SportsCoachBookings.Bookings.Booking
  alias SportsCoachBookings.Commerce
  alias SportsCoachBookings.Credits
  alias SportsCoachBookings.Customers
  alias SportsCoachBookings.DataCase
  alias SportsCoachBookings.Repo
  alias SportsCoachBookings.Scheduling.Session
  alias SportsCoachBookings.Tenancy

  @owner_email "owner@acme.test"
  @customer_email "dana@acme.test"

  describe "golden path: onboard, purchase, book, attend, feedback" do
    setup do
      slug = "acme-#{System.unique_integer([:positive])}"

      signup_resp =
        signup(build_conn(), %{name: "Acme Coaching", slug: slug, email: @owner_email})

      assert %{"tenant" => %{"slug" => ^slug}} = json_response(signup_resp, 201)
      tenant = Tenancy.get_tenant_by_slug(slug)

      # tenant.created seeds the default cancellation policy (transactional outbox).
      drain_outbox()

      owner = ConnTest.recycle(signup_resp) |> host(slug)

      %{tenant: tenant, slug: slug, owner: owner}
    end

    test "the whole journey succeeds and every invariant holds", ctx do
      %{tenant: tenant, slug: slug, owner: owner} = ctx

      # 1. Branding is stored and exposed on the public portal branding endpoint.
      branding =
        owner
        |> json_patch("/api/staff/branding", %{
          "branding" => %{"primary_color" => "#0f766e", "text_color" => "#0b1220"}
        })
        |> json_response(200)

      assert branding["primary_color"] == "#0f766e"

      public_branding =
        build_conn() |> host(slug) |> get("/api/portal/branding") |> json_response(200)

      assert public_branding["theme"]["primary_color"] == "#0f766e"

      # 2. Connect the Fake payment provider and refresh readiness.
      assert %{"url" => url} =
               owner
               |> post("/api/staff/payments/connect/onboarding")
               |> json_response(200)

      assert url =~ "provider.fake"

      assert %{"charges_enabled" => true} =
               owner
               |> get("/api/staff/payments/connect")
               |> json_response(200)

      # 3. Catalog: venue → offering → package.
      venue =
        owner
        |> json_post("/api/staff/catalog/venues", %{"name" => "Main Field"})
        |> json_response(201)

      offering =
        owner
        |> json_post("/api/staff/catalog/offerings", %{
          "name" => "U10 Skills",
          "format" => "group",
          "duration_minutes" => 60,
          "default_capacity" => 8,
          "credit_cost" => 1
        })
        |> json_response(201)

      package =
        owner
        |> json_post("/api/staff/catalog/packages", %{
          "name" => "5-Session Pack",
          "credit_quantity" => 5,
          "price" => 5_000
        })
        |> json_response(201)

      assert package["credit_quantity"] == 5

      # 4. Schedule a session and publish a waiver that applies to all bookings.
      starts_at = DateTime.utc_now() |> DateTime.add(3, :day) |> DateTime.truncate(:microsecond)

      session =
        owner
        |> json_post("/api/staff/schedule/sessions", %{
          "offering_id" => offering["id"],
          "venue_id" => venue["id"],
          "starts_at" => DateTime.to_iso8601(starts_at)
        })
        |> json_response(201)
        |> Map.fetch!("session")

      assert session["capacity"] == 8

      # A recurring series materialises its occurrences too.
      series =
        owner
        |> json_post("/api/staff/schedule/series", %{
          "offering_id" => offering["id"],
          "venue_id" => venue["id"],
          "weekdays" => [2],
          "start_time_local" => "17:00",
          "duration_minutes" => 60,
          "starts_on" => Date.add(Date.utc_today(), 7) |> Date.to_iso8601(),
          "ends_on" => Date.add(Date.utc_today(), 35) |> Date.to_iso8601()
        })
        |> json_response(201)

      assert %{"series" => %{"weekdays" => [2]}, "sessions" => sessions} = series
      assert sessions != []

      template =
        owner
        |> json_post("/api/staff/waivers/templates", %{
          "template" => %{"name" => "Liability", "scope" => "all_bookings"}
        })
        |> json_response(201)

      draft =
        owner
        |> json_post("/api/staff/waivers/templates/#{template["id"]}/versions", %{
          "version" => %{"body_markdown" => "I accept the risks of play."}
        })
        |> json_response(201)

      published =
        owner
        |> json_post("/api/staff/waivers/versions/#{draft["id"]}/publish", %{})
        |> json_response(200)

      assert published["status"] == "published"

      # 5. Customer registers (per tenant) and confirms their email.
      reg_conn = register_customer(build_conn(), slug, @customer_email)
      assert %{"household" => %{"id" => household_id}} = json_response(reg_conn, 201)
      customer = ConnTest.recycle(reg_conn)

      confirm_email(tenant, slug, @customer_email)

      # 6. Add a player + emergency contact, then sign the required waiver.
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

      assert player["household_id"] == household_id

      assert %{"id" => _} =
               customer
               |> json_post("/api/portal/players/#{player["id"]}/emergency_contacts", %{
                 "emergency_contact" => %{
                   "name" => "Dana Reyes",
                   "relationship" => "Parent",
                   "phone" => "+19025550111",
                   "priority" => 1
                 }
               })
               |> json_response(201)

      # Invariant 4: a booking cannot be created until the waiver is signed.
      blocked =
        customer
        |> json_post("/api/portal/bookings", %{
          "player_id" => player["id"],
          "session_id" => session["id"],
          "method" => "credits"
        })

      assert json_response(blocked, 422)["error"]["code"] == "waivers_required"

      signed =
        customer
        |> json_post("/api/portal/players/#{player["id"]}/waivers/#{published["id"]}/sign", %{
          "signature" => %{
            "content_sha256" => published["content_sha256"],
            "signer_name_typed" => "Dana Reyes",
            "signer_relationship" => "Parent",
            "consent_checkbox" => true
          }
        })
        |> json_response(201)

      assert signed["content_sha256"] == published["content_sha256"]

      # 7. Buy the package: cart → checkout (Fake) → webhook → order.paid → credits.
      assert %{"lines" => [%{"type" => "package"}]} =
               customer
               |> json_post("/api/portal/cart/lines", %{
                 "line" => %{"type" => "package", "ref_id" => package["id"], "quantity" => 1}
               })
               |> json_response(201)

      checkout = customer |> post("/api/portal/checkout") |> json_response(201)
      order_id = checkout["order"]["id"]
      assert checkout["order"]["status"] == "pending_payment"
      assert checkout["order"]["total"] == 5_000
      assert checkout["redirect_url"] =~ "provider.fake"

      assert %{"received" => true} =
               complete_checkout(build_conn(), tenant, order_id, 5_000) |> json_response(200)

      drain_outbox()
      DataCase.put_tenant(tenant)
      assert Commerce.get_order!(order_id).status == :paid

      # Invariant 3: the balance equals the sum of the append-only ledger.
      assert {:ok, 5} = Credits.reconcile(household_id)
      assert [%{offering_id: :any, amount: 5}] = Credits.balance(household_id)
      assert Credits.list_ledger(household_id) |> Enum.sum_by(& &1.delta) == 5

      # 8. Book a session with credits; capacity counts stay consistent.
      booking =
        customer
        |> json_post("/api/portal/bookings", %{
          "player_id" => player["id"],
          "session_id" => session["id"],
          "method" => "credits"
        })
        |> json_response(201)

      assert booking["status"] == "confirmed"
      assert booking["credits_used"] == 1

      DataCase.put_tenant(tenant)
      assert Credits.balance(household_id) |> Enum.sum_by(& &1.amount) == 4
      assert {:ok, 4} = Credits.reconcile(household_id)

      fresh_session = Repo.get!(Session, session["id"])
      assert {fresh_session.booked_count, fresh_session.held_count} == {1, 0}
      assert fresh_session.booked_count + fresh_session.held_count <= fresh_session.capacity

      # 9. Roster + attendance (shift the session into the past so the window opens).
      roster =
        owner
        |> get("/api/staff/sessions/#{session["id"]}/roster")
        |> json_response(200)

      assert [%{"player_id" => player_id, "status" => "confirmed"}] = roster["data"]
      assert player_id == player["id"]

      shift_into_past(session["id"])
      DataCase.put_tenant(tenant)

      attended =
        owner
        |> json_post("/api/staff/bookings/#{booking["id"]}/attendance", %{"status" => "attended"})
        |> json_response(200)

      assert attended["status"] == "attended"

      # 10. Coach/owner feedback, shared with the household.
      feedback =
        owner
        |> json_post("/api/staff/feedback", %{
          "session_id" => session["id"],
          "player_id" => player["id"],
          "body" => "Great first touch.",
          "visibility" => "shared"
        })
        |> json_response(201)

      assert feedback["visibility"] == "shared"

      drain_outbox()
      DataCase.put_tenant(tenant)

      # 11. The relevant emails were queued (delivery rows created by subscribers).
      templates = delivered_templates(@customer_email)
      assert "customer_welcome" in templates
      assert "order_receipt" in templates
      assert "credits_granted" in templates
      assert "booking_confirmed" in templates
      assert "waiver_signed" in templates
      assert "feedback_shared" in templates
      assert "booking_attended" in templates

      # Invariant 1: the booking is tenant-scoped at the RLS layer.
      assert Repo.get(Booking, booking["id"]).tenant_id == tenant.id
    end

    test "invariant 3 + 6: the ledger is append-only and a replayed webhook grants once",
         ctx do
      %{tenant: tenant, slug: slug, owner: owner} = ctx

      owner |> post("/api/staff/payments/connect/onboarding")
      owner |> get("/api/staff/payments/connect") |> json_response(200)

      package =
        owner
        |> json_post("/api/staff/catalog/packages", %{
          "name" => "3-Pack",
          "credit_quantity" => 3,
          "price" => 3_000
        })
        |> json_response(201)

      offering =
        owner
        |> json_post("/api/staff/catalog/offerings", %{
          "name" => "Mini",
          "format" => "group",
          "duration_minutes" => 45,
          "credit_cost" => 1
        })
        |> json_response(201)

      venue =
        owner
        |> json_post("/api/staff/catalog/venues", %{"name" => "Pitch"})
        |> json_response(201)

      session =
        owner
        |> json_post("/api/staff/schedule/sessions", %{
          "offering_id" => offering["id"],
          "venue_id" => venue["id"],
          "starts_at" => future_iso(2)
        })
        |> json_response(201)
        |> Map.fetch!("session")

      reg_conn = register_customer(build_conn(), slug, @customer_email)
      assert %{"household" => %{"id" => household_id}} = json_response(reg_conn, 201)
      customer = ConnTest.recycle(reg_conn)
      confirm_email(tenant, slug, @customer_email)

      player =
        customer
        |> json_post("/api/portal/players", %{
          "player" => %{
            "first_name" => "Alex",
            "last_name" => "Reyes",
            "date_of_birth" => "2015-01-01"
          }
        })
        |> json_response(201)

      customer
      |> json_post("/api/portal/players/#{player["id"]}/emergency_contacts", %{
        "emergency_contact" => %{"name" => "Dana", "phone" => "+19025550111", "priority" => 1}
      })
      |> json_response(201)

      customer
      |> json_post("/api/portal/cart/lines", %{
        "line" => %{"type" => "package", "ref_id" => package["id"], "quantity" => 1}
      })
      |> json_response(201)

      checkout = customer |> post("/api/portal/checkout") |> json_response(201)
      order_id = checkout["order"]["id"]

      # Invariant 6: replaying the webhook never double-fulfils or double-grants.
      for _ <- 1..3 do
        assert %{"received" => true} =
                 complete_checkout(build_conn(), tenant, order_id, 3_000) |> json_response(200)
      end

      drain_outbox()
      DataCase.put_tenant(tenant)

      assert length(Credits.list_lots(household_id)) == 1
      assert Credits.list_ledger(household_id) |> Enum.sum_by(& &1.delta) == 3
      assert {:ok, 3} = Credits.reconcile(household_id)

      booking =
        customer
        |> json_post("/api/portal/bookings", %{
          "player_id" => player["id"],
          "session_id" => session["id"],
          "method" => "credits"
        })
        |> json_response(201)

      drain_outbox()
      DataCase.put_tenant(tenant)

      assert Credits.list_ledger(household_id) |> Enum.sum_by(& &1.delta) == 2
      assert {:ok, 2} = Credits.reconcile(household_id)

      # Cancelling inside the 24h+ window returns the credit via a reversal entry.
      cancelled =
        customer
        |> json_post("/api/portal/bookings/#{booking["id"]}/cancel", %{"reason" => "change"})
        |> json_response(200)

      assert cancelled["cancel_outcome"]["credit_outcome"] == "return"

      drain_outbox()
      DataCase.put_tenant(tenant)

      ledger = Credits.list_ledger(household_id)
      # grant + debit + reversal — no entry was mutated or deleted.
      assert length(ledger) == 3
      assert Enum.sum(Enum.map(ledger, & &1.delta)) == 3
      assert {:ok, 3} = Credits.reconcile(household_id)
    end

    test "staff can log out and log back in with a password", ctx do
      %{slug: slug, owner: owner} = ctx

      logged_out = owner |> delete("/api/platform/session")
      assert response(logged_out, 204)

      login = staff_login(build_conn(), @owner_email)
      assert %{"staff_user" => %{"email" => @owner_email}} = json_response(login, 201)

      settings = login |> host(slug) |> get("/api/staff/settings") |> json_response(200)
      assert settings["tenant"]["slug"] == slug
    end
  end

  ## Helpers

  defp confirm_email(tenant, slug, email) do
    DataCase.put_tenant(tenant)
    user = Customers.get_customer_user_by_email(email)
    token = Customers.create_confirm_token(user)

    build_conn()
    |> host(slug)
    |> json_post("/api/portal/confirmation", %{token: token})
    |> json_response(200)
  end

  defp shift_into_past(session_id) do
    past = DateTime.add(DateTime.utc_now(), -3600, :second) |> DateTime.truncate(:microsecond)

    Repo.update_all(
      from(s in Session, where: s.id == ^session_id),
      set: [starts_at: past, ends_at: DateTime.add(past, 3600, :second)]
    )
  end
end
