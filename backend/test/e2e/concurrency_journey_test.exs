defmodule SportsCoachBookings.E2E.ConcurrencyJourneyTest do
  @moduledoc """
  WP-18 end-to-end: the capacity invariant (invariant 2) holds under many
  concurrent HTTP booking requests against one session.

  A session with capacity 5 is hammered with 25 simultaneous requests, each for
  a distinct player. Exactly 5 must be confirmed and the rest rejected with
  `409 session_full`; `booked_count + held_count` must never exceed capacity.
  """
  use SportsCoachBookingsWeb.ConnCase, async: false

  import Ecto.Query
  import SportsCoachBookings.E2EHelpers

  alias Phoenix.ConnTest
  alias SportsCoachBookings.Customers
  alias SportsCoachBookings.DataCase
  alias SportsCoachBookings.Players
  alias SportsCoachBookings.Repo
  alias SportsCoachBookings.Scheduling.Session

  @customer_email "dana@concurrency.test"

  test "concurrent bookings never oversell a session" do
    %{tenant: tenant, slug: slug, owner: owner} =
      onboard_tenant(build_conn(), %{
        name: "Concurrency Co",
        slug: "conc-#{System.unique_integer([:positive])}",
        email: "owner@concurrency.test"
      })

    venue =
      owner
      |> json_post("/api/staff/catalog/venues", %{"name" => "Field"})
      |> json_response(201)

    offering =
      owner
      |> json_post("/api/staff/catalog/offerings", %{
        "name" => "Free Group",
        "format" => "group",
        "duration_minutes" => 60,
        "default_capacity" => 5,
        "credit_cost" => 0
      })
      |> json_response(201)

    capacity = 5

    session =
      owner
      |> json_post("/api/staff/schedule/sessions", %{
        "offering_id" => offering["id"],
        "venue_id" => venue["id"],
        "capacity" => capacity,
        "starts_at" => future_iso(3)
      })
      |> json_response(201)
      |> Map.fetch!("session")

    reg_conn = register_customer(build_conn(), slug, @customer_email)
    assert %{"household" => %{"id" => household_id}} = json_response(reg_conn, 201)

    DataCase.put_tenant(tenant)
    user = Customers.get_customer_user_by_email(@customer_email)
    token = Customers.create_confirm_token(user)
    build_conn() |> host(slug) |> json_post("/api/portal/confirmation", %{token: token})

    customer = ConnTest.recycle(reg_conn)

    DataCase.put_tenant(tenant)

    player_ids =
      for n <- 1..25 do
        {:ok, player} =
          Players.create_player(nil, %{
            household_id: household_id,
            first_name: "Player",
            last_name: "Number#{n}",
            date_of_birth: ~D[2015-05-01]
          })

        {:ok, _} =
          Players.create_emergency_contact(player, %{
            name: "Guardian",
            relationship: "Parent",
            phone: "+19025550111",
            priority: 1
          })

        player.id
      end

    # Fire all 25 at once. The shared sandbox serialises the transactions onto
    # one connection, exactly like a single-capacity-per-session race.
    results =
      player_ids
      |> Task.async_stream(
        fn player_id ->
          customer
          |> json_post("/api/portal/bookings", %{
            "player_id" => player_id,
            "session_id" => session["id"],
            "method" => "credits"
          })
          |> json_response_or_status()
        end,
        max_concurrency: 25,
        ordered: false,
        timeout: 60_000
      )
      |> Enum.map(fn {:ok, result} -> result end)

    confirmed = Enum.count(results, &match?({201, _}, &1))
    rejected = Enum.count(results, &match?({409, %{"error" => %{"code" => "session_full"}}}, &1))

    assert confirmed == capacity
    assert rejected == 25 - capacity

    DataCase.put_tenant(tenant)
    fresh = Repo.get!(Session, session["id"])

    assert fresh.booked_count == capacity
    assert fresh.booked_count + fresh.held_count <= fresh.capacity

    # The database check constraint is the final backstop: a direct oversell fails.
    assert_raise Postgrex.Error, fn ->
      Repo.update_all(
        from(s in Session, where: s.id == ^fresh.id),
        set: [held_count: fresh.capacity]
      )
    end
  end

  defp json_response_or_status(conn) do
    {conn.status, Jason.decode!(conn.resp_body)}
  end
end
