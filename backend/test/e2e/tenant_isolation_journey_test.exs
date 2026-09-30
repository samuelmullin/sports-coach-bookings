defmodule SportsCoachBookings.E2E.TenantIsolationJourneyTest do
  @moduledoc """
  WP-18 end-to-end: invariant 1 — no query, request, or session ever crosses a
  tenant boundary. Two tenants with the same customer email are exercised
  through the real HTTP API, and the booking row is checked with raw SQL so the
  RLS policy (not just Ecto scoping) is proven.
  """
  use SportsCoachBookingsWeb.ConnCase, async: false

  import SportsCoachBookings.E2EHelpers

  alias Phoenix.ConnTest
  alias SportsCoachBookings.Bookings
  alias SportsCoachBookings.Customers
  alias SportsCoachBookings.DataCase
  alias SportsCoachBookings.Repo

  @shared_email "same@isolation.test"

  setup do
    a =
      onboard_tenant(build_conn(), %{
        name: "Alpha",
        slug: "alpha-#{System.unique_integer([:positive])}",
        email: "owner-alpha@isolation.test"
      })

    b =
      onboard_tenant(build_conn(), %{
        name: "Beta",
        slug: "beta-#{System.unique_integer([:positive])}",
        email: "owner-beta@isolation.test"
      })

    %{a: bootstrap(a), b: bootstrap(b)}
  end

  test "the same email is two independent accounts and sessions are host-scoped", %{
    a: a,
    b: b
  } do
    assert a.household_id != b.household_id

    # Alpha's customer session is not a Beta session.
    denied = a.customer |> host(b.slug) |> get("/api/portal/account")
    assert json_response(denied, 403)["error"]["code"] == "forbidden"

    # Alpha's staff session has no membership in Beta.
    denied_staff = a.owner |> host(b.slug) |> get("/api/staff/settings")
    assert json_response(denied_staff, 403)["error"]["code"] == "forbidden"

    # Each session still works on its own host.
    assert json_response(a.customer |> host(a.slug) |> get("/api/portal/account"), 200)
    assert json_response(b.customer |> host(b.slug) |> get("/api/portal/account"), 200)
  end

  test "one tenant cannot read another tenant's player or booking", %{a: a, b: b} do
    # Alpha player is invisible from Beta's customer session.
    read =
      b.customer
      |> host(b.slug)
      |> get("/api/portal/players/#{a.player_id}")

    # Cross-tenant rows are hidden entirely (404) rather than merely forbidden.
    assert json_response(read, 404)["error"]["code"] == "not_found"

    # Alpha's booking cannot be previewed/cancelled from Beta.
    preview =
      b.customer
      |> host(b.slug)
      |> get("/api/portal/bookings/#{a.booking_id}/cancel-preview")

    assert json_response(preview, 404)["error"]["code"] == "not_found"

    # Invariant 1 at the storage layer: with Beta in context, Alpha's row is
    # invisible through Ecto *and* through raw SQL (RLS).
    DataCase.put_tenant(b.tenant)
    refute Repo.get(SportsCoachBookings.Bookings.Booking, a.booking_id)

    assert SportsCoachBookings.TenantIsolation.raw_count("bookings", a.booking_id) == 0

    # And Alpha can still read its own booking.
    DataCase.put_tenant(a.tenant)
    assert %{id: id} = Bookings.get_booking!(a.booking_id)
    assert id == a.booking_id
  end

  test "a customer only exists in the tenant where they registered", %{a: a, b: b} do
    # A distinct-email customer created on Alpha cannot authenticate on Beta.
    reg = register_customer(build_conn(), a.slug, "alpha-only@isolation.test")
    assert json_response(reg, 201)

    DataCase.put_tenant(a.tenant)
    user = Customers.get_customer_user_by_email("alpha-only@isolation.test")
    token = Customers.create_confirm_token(user)
    build_conn() |> host(a.slug) |> json_post("/api/portal/confirmation", %{token: token})

    bad_login =
      build_conn()
      |> host(b.slug)
      |> json_post("/api/portal/session", %{
        email: "alpha-only@isolation.test",
        password: password()
      })

    assert json_response(bad_login, 401)["error"]["code"] == "invalid_credentials"

    good_login =
      build_conn()
      |> host(a.slug)
      |> json_post("/api/portal/session", %{
        email: "alpha-only@isolation.test",
        password: password()
      })

    assert json_response(good_login, 201)
  end

  ## Helpers

  defp bootstrap(%{tenant: tenant, slug: slug, owner: owner}) do
    reg_conn = register_customer(build_conn(), slug, @shared_email)
    assert %{"household" => %{"id" => household_id}} = json_response(reg_conn, 201)

    DataCase.put_tenant(tenant)
    user = Customers.get_customer_user_by_email(@shared_email)
    token = Customers.create_confirm_token(user)
    build_conn() |> host(slug) |> json_post("/api/portal/confirmation", %{token: token})

    customer = ConnTest.recycle(reg_conn)

    venue =
      owner
      |> json_post("/api/staff/catalog/venues", %{"name" => "Field"})
      |> json_response(201)

    offering =
      owner
      |> json_post("/api/staff/catalog/offerings", %{
        "name" => "Group",
        "format" => "group",
        "duration_minutes" => 60,
        "credit_cost" => 0
      })
      |> json_response(201)

    session =
      owner
      |> json_post("/api/staff/schedule/sessions", %{
        "offering_id" => offering["id"],
        "venue_id" => venue["id"],
        "starts_at" => future_iso(3)
      })
      |> json_response(201)
      |> Map.fetch!("session")

    player =
      customer
      |> json_post("/api/portal/players", %{
        "player" => %{
          "first_name" => "Same",
          "last_name" => "Player",
          "date_of_birth" => "2016-04-01"
        }
      })
      |> json_response(201)

    customer
    |> json_post("/api/portal/players/#{player["id"]}/emergency_contacts", %{
      "emergency_contact" => %{"name" => "Guardian", "phone" => "+19025550111", "priority" => 1}
    })
    |> json_response(201)

    booking =
      customer
      |> json_post("/api/portal/bookings", %{
        "player_id" => player["id"],
        "session_id" => session["id"],
        "method" => "credits"
      })
      |> json_response(201)

    %{
      tenant: tenant,
      slug: slug,
      owner: owner,
      customer: customer,
      household_id: household_id,
      player_id: player["id"],
      booking_id: booking["id"]
    }
  end
end
