defmodule SportsCoachBookingsWeb.Portal.ReservationsControllerTest do
  use SportsCoachBookingsWeb.ConnCase, async: false

  import Ecto.Query

  alias SportsCoachBookings.Core.CustomerActor
  alias SportsCoachBookings.Credits
  alias SportsCoachBookings.Players
  alias SportsCoachBookings.Repo
  alias SportsCoachBookings.Reservations.Reservation
  alias SportsCoachBookings.Scheduling.Session

  setup do
    tenant = insert(:tenant, slug: "reservations-#{System.unique_integer([:positive])}")
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

  defp json_post(conn, path, payload) do
    conn
    |> put_req_header("content-type", "application/json")
    |> post(path, Jason.encode!(payload))
  end

  defp session(venue, offering, days \\ 3, capacity \\ 5) do
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

  defp player(household) do
    unique = System.unique_integer([:positive])

    {:ok, player} =
      Players.create_player(nil, %{
        household_id: household,
        first_name: "Sam",
        last_name: "Player #{unique}",
        date_of_birth: ~D[2015-05-01]
      })

    {:ok, _contact} =
      Players.create_emergency_contact(player, %{
        name: "Parent",
        relationship: "Parent",
        phone: "+5555550100",
        priority: 1
      })

    player
  end

  defp create_reservation(conn, tenant, sessions, offering_id \\ nil) do
    payload = %{"sessions" => Enum.map(sessions, & &1.id)}
    payload = if offering_id, do: Map.put(payload, "offering_id", offering_id), else: payload

    conn
    |> with_host(tenant.slug)
    |> json_post("/api/portal/reservations", payload)
    |> json_response(201)
  end

  test "anonymous create, show, extend, and delete", %{
    conn: conn,
    tenant: tenant,
    venue: venue
  } do
    offering = insert(:offering)
    s = session(venue, offering)

    created = create_reservation(conn, tenant, [s], offering.id)
    token = created["token"]
    id = created["id"]

    assert is_binary(token)
    assert created["status"] == "active"
    assert [%{"session_id" => sid}] = created["sessions"]
    assert sid == s.id
    assert Repo.get!(Session, s.id).held_count == 1

    show =
      conn
      |> with_host(tenant.slug)
      |> put_req_header("x-reservation-token", token)
      |> get("/api/portal/reservations/#{id}")
      |> json_response(200)

    assert show["id"] == id
    assert show["status"] == "active"

    extended =
      conn
      |> with_host(tenant.slug)
      |> put_req_header("x-reservation-token", token)
      |> json_post("/api/portal/reservations/#{id}/extend", %{})
      |> json_response(200)

    assert extended["expires_at"]

    conn
    |> with_host(tenant.slug)
    |> put_req_header("x-reservation-token", token)
    |> delete("/api/portal/reservations/#{id}")
    |> response(204)

    assert Repo.get!(Session, s.id).held_count == 0
    assert Repo.get!(Reservation, id).status == :released
  end

  test "a missing token is 401 and a bad token is 404", %{
    conn: conn,
    tenant: tenant,
    venue: venue
  } do
    offering = insert(:offering)
    s = session(venue, offering)
    created = create_reservation(conn, tenant, [s])
    path = "/api/portal/reservations/#{created["id"]}"

    assert conn
           |> with_host(tenant.slug)
           |> get(path)
           |> json_response(401)

    assert conn
           |> with_host(tenant.slug)
           |> put_req_header("x-reservation-token", "not-the-token")
           |> get(path)
           |> json_response(404)
  end

  test "convert requires a customer and books with credits", %{
    conn: conn,
    tenant: tenant,
    venue: venue
  } do
    household = insert(:household).id
    offering = insert(:offering, credit_cost: 1)
    s = session(venue, offering)
    player = player(household)
    {:ok, _} = Credits.grant_complimentary(nil, household, %{amount: 5})

    created = create_reservation(conn, tenant, [s], offering.id)
    token = created["token"]
    id = created["id"]

    converted =
      conn
      |> customer(tenant, household)
      |> put_req_header("x-reservation-token", token)
      |> json_post("/api/portal/reservations/#{id}/convert", %{
        "assignments" => [
          %{"session_id" => s.id, "player_id" => player.id, "method" => "credits"}
        ]
      })
      |> json_response(200)

    assert [%{"payment_method" => "credits", "session_id" => session_id}] = converted["bookings"]
    assert session_id == s.id
    assert Repo.get!(Session, s.id).booked_count == 1
    assert Repo.get!(Session, s.id).held_count == 0
    assert Repo.get!(Reservation, id).status == :converted
    assert Repo.get!(Reservation, id).household_id == household
  end

  test "convert after expiry is 409 reservation_expired", %{
    conn: conn,
    tenant: tenant,
    venue: venue
  } do
    household = insert(:household).id
    offering = insert(:offering, credit_cost: 0)
    s = session(venue, offering)
    player = player(household)

    created = create_reservation(conn, tenant, [s])
    token = created["token"]
    id = created["id"]

    past = DateTime.add(DateTime.utc_now(), -60, :second)

    Repo.update_all(
      from(r in Reservation, where: r.id == ^id),
      set: [expires_at: past]
    )

    body = %{
      "assignments" => [
        %{"session_id" => s.id, "player_id" => player.id, "method" => "credits"}
      ]
    }

    response =
      conn
      |> customer(tenant, household)
      |> put_req_header("x-reservation-token", token)
      |> json_post("/api/portal/reservations/#{id}/convert", body)
      |> json_response(409)

    assert response["error"]["code"] == "reservation_expired"
    assert Repo.get!(Reservation, id).status == :active
    assert Repo.get!(Session, s.id).held_count == 1
  end

  test "creating on a full session is 409 session_full", %{
    conn: conn,
    tenant: tenant,
    venue: venue
  } do
    offering = insert(:offering)
    s = session(venue, offering, 3, 1)
    create_reservation(conn, tenant, [s])

    response =
      conn
      |> with_host(tenant.slug)
      |> json_post("/api/portal/reservations", %{"sessions" => [s.id]})
      |> json_response(409)

    assert response["error"]["code"] == "session_full"
    assert response["error"]["details"]["session_id"] == s.id
  end
end
