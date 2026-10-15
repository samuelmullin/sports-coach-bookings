defmodule SportsCoachBookingsWeb.Portal.BookingsControllerTest do
  use SportsCoachBookingsWeb.ConnCase, async: false

  import Ecto.Query

  alias SportsCoachBookings.Core.CustomerActor
  alias SportsCoachBookings.Credits
  alias SportsCoachBookings.Players
  alias SportsCoachBookings.Repo
  alias SportsCoachBookings.Scheduling.Session

  setup do
    tenant = insert(:tenant, slug: "portal-bookings-#{System.unique_integer([:positive])}")
    SportsCoachBookings.DataCase.put_tenant(tenant)
    venue = insert(:venue)
    %{tenant: tenant, venue: venue}
  end

  defp customer(conn, tenant, household) do
    actor =
      CustomerActor.new(
        customer_user_id: Ecto.UUID.generate(),
        household_id: household,
        tenant_id: tenant.id
      )

    conn
    |> with_host(tenant.slug)
    |> Plug.Conn.assign(:current_customer_actor, actor)
    |> Plug.Conn.assign(:tenant, tenant)
  end

  defp player(household) do
    {:ok, player} =
      Players.create_player(nil, %{
        household_id: household,
        first_name: "Test",
        last_name: "Player #{System.unique_integer([:positive])}",
        date_of_birth: ~D[2015-05-01]
      })

    {:ok, _} =
      Players.create_emergency_contact(player, %{
        name: "Parent",
        relationship: "Parent",
        phone: "+15555550100",
        priority: 1
      })

    player
  end

  defp session(venue, offering, days, capacity \\ 5) do
    starts_at =
      DateTime.utc_now()
      |> DateTime.add(days * 86_400, :second)
      |> DateTime.truncate(:microsecond)

    insert(:session,
      offering_id: offering.id,
      venue_id: venue.id,
      capacity: capacity,
      starts_at: starts_at,
      ends_at: DateTime.add(starts_at, 3600, :second)
    )
  end

  defp json_post(conn, path, payload) do
    conn
    |> put_req_header("content-type", "application/json")
    |> post(path, Jason.encode!(payload))
  end

  test "books with credits, lists, previews, and cancels", %{
    conn: conn,
    tenant: tenant,
    venue: venue
  } do
    household = insert(:household).id
    offering = insert(:offering, credit_cost: 1)
    session = session(venue, offering, 3)
    player = player(household)
    {:ok, _} = Credits.grant_complimentary(nil, household, %{amount: 5})

    conn = customer(conn, tenant, household)

    created =
      conn
      |> json_post("/api/portal/bookings", %{
        "player_id" => player.id,
        "session_id" => session.id,
        "method" => "credits"
      })
      |> json_response(201)

    assert created["status"] == "confirmed"
    assert created["credits_used"] == 1

    listing = conn |> get("/api/portal/bookings") |> json_response(200)
    assert [%{"booking" => %{"id" => id}}] = listing["data"]
    assert id == created["id"]

    preview =
      conn
      |> get("/api/portal/bookings/#{created["id"]}/cancel-preview")
      |> json_response(200)

    assert preview["outcome"]["credit_outcome"] == "return"
    assert preview["already_cancelled"] == false

    cancelled =
      conn
      |> json_post("/api/portal/bookings/#{created["id"]}/cancel", %{"reason" => "nope"})
      |> json_response(200)

    assert cancelled["status"] == "cancelled"
    assert Credits.available_for_offering(household, offering.id) == 5
  end

  test "an unconfirmed customer cannot book (403 email_unconfirmed)", %{
    conn: conn,
    tenant: tenant,
    venue: venue
  } do
    household = insert(:household).id
    offering = insert(:offering, credit_cost: 1)
    session = session(venue, offering, 3)
    player = player(household)
    {:ok, _} = Credits.grant_complimentary(nil, household, %{amount: 5})

    unconfirmed = %SportsCoachBookings.Customers.CustomerUser{
      id: Ecto.UUID.generate(),
      tenant_id: tenant.id,
      confirmed_at: nil
    }

    actor =
      CustomerActor.new(
        customer_user_id: unconfirmed.id,
        household_id: household,
        tenant_id: tenant.id,
        customer_user: unconfirmed
      )

    conn = conn |> customer(tenant, household) |> Plug.Conn.assign(:current_customer_actor, actor)

    body =
      conn
      |> json_post("/api/portal/bookings", %{
        "player_id" => player.id,
        "session_id" => session.id,
        "method" => "credits"
      })
      |> json_response(403)

    assert body["error"]["code"] == "email_unconfirmed"
    assert Credits.available_for_offering(household, offering.id) == 5
  end

  test "rebooks into another session", %{conn: conn, tenant: tenant, venue: venue} do
    household = insert(:household).id
    offering = insert(:offering, credit_cost: 1)
    source = session(venue, offering, 3)
    target = session(venue, offering, 4)
    player = player(household)
    {:ok, _} = Credits.grant_complimentary(nil, household, %{amount: 5})

    conn = customer(conn, tenant, household)

    created =
      conn
      |> json_post("/api/portal/bookings", %{
        "player_id" => player.id,
        "session_id" => source.id,
        "method" => "credits"
      })
      |> json_response(201)

    options =
      conn
      |> get("/api/portal/bookings/#{created["id"]}/rebook-options")
      |> json_response(200)

    assert options["allowed"] == true
    assert Enum.any?(options["sessions"], &(&1["session"]["id"] == target.id))

    rebooked =
      conn
      |> json_post("/api/portal/bookings/#{created["id"]}/rebook", %{
        "target_session_id" => target.id
      })
      |> json_response(201)

    assert rebooked["session_id"] == target.id
    assert rebooked["rebooked_from_id"] == created["id"]
    assert Repo.get!(Session, source.id).booked_count == 0
    assert Repo.get!(Session, target.id).booked_count == 1
  end

  test "a full session returns 409 session_full", %{conn: conn, tenant: tenant, venue: venue} do
    household = insert(:household).id
    offering = insert(:offering, credit_cost: 0)
    session = session(venue, offering, 3, 1)
    p1 = player(household)
    p2 = player(household)
    {:ok, _} = Credits.grant_complimentary(nil, household, %{amount: 5})
    fill_session(session, p1)
    conn = customer(conn, tenant, household)

    resp =
      conn
      |> json_post("/api/portal/bookings", %{
        "player_id" => p2.id,
        "session_id" => session.id,
        "method" => "credits"
      })
      |> json_response(409)

    assert resp["error"]["code"] == "session_full"
  end

  defp fill_session(session, player) do
    Repo.update_all(
      from(s in Session, where: s.id == ^session.id),
      set: [booked_count: 1]
    )

    insert(:booking,
      session_id: session.id,
      player_id: player.id,
      household_id: player.household_id
    )
  end
end
