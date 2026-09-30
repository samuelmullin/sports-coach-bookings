defmodule SportsCoachBookings.ReservationsTest do
  use SportsCoachBookings.DataCase, async: false

  alias SportsCoachBookings.Core.CustomerActor
  alias SportsCoachBookings.Core.TenantContext
  alias SportsCoachBookings.Credits
  alias SportsCoachBookings.Players
  alias SportsCoachBookings.Repo
  alias SportsCoachBookings.Reservations
  alias SportsCoachBookings.Reservations.Reservation
  alias SportsCoachBookings.Scheduling.Session

  setup do
    tenant = insert(:tenant)
    put_tenant(tenant)
    %{tenant: tenant}
  end

  describe "create/1" do
    test "holds one seat per session and returns a one-time token" do
      s1 = session()
      s2 = session()

      assert {:ok, %{reservation: reservation, token: token}} =
               Reservations.create(%{sessions: [s1.id, s2.id]})

      assert is_binary(token)
      assert reservation.status == :active
      assert reservation.expires_at != nil
      assert reservation.last_activity_at != nil

      assert %{starts_at: _, ends_at: _} =
               Enum.find(reservation.session_summaries, &(&1.session_id == s1.id))

      assert held_count(s1) == 1
      assert held_count(s2) == 1
      assert booked_count(s1) == 0

      # The stored value is the hash, never the token.
      stored = Repo.get!(Reservation, reservation.id)
      assert stored.token_hash == :crypto.hash(:sha256, token)
      refute stored.token_hash == token
    end

    test "a full session returns {:error, {:session_full, id}} with no partial holds" do
      full = session(capacity: 1)
      other = session()

      assert {:ok, _} = Reservations.create(%{sessions: [full.id]})

      assert {:error, {:session_full, session_id}} =
               Reservations.create(%{sessions: [other.id, full.id]})

      assert session_id == full.id
      # The second create must not have left a hold on `other`.
      assert held_count(other) == 0
      assert held_count(full) == 1
    end

    test "an unknown session returns {:error, {:invalid_session, id}} with no partial holds" do
      valid = session()
      bogus = Ecto.UUID.generate()

      assert {:error, {:invalid_session, session_id}} =
               Reservations.create(%{sessions: [valid.id, bogus]})

      assert session_id == bogus
      assert held_count(valid) == 0
    end

    test "requires at least one session" do
      assert {:error, {:invalid_sessions, _message}} = Reservations.create(%{sessions: []})
    end
  end

  describe "fetch/2" do
    test "returns the reservation for the matching token, regardless of status" do
      s = session()
      {:ok, %{reservation: reservation, token: token}} = Reservations.create(%{sessions: [s.id]})

      assert {:ok, fetched} = Reservations.fetch(reservation.id, token)
      assert fetched.id == reservation.id
      assert [%{session_id: session_id}] = fetched.session_summaries
      assert session_id == s.id
    end

    test "returns :not_found for a bad token or unknown id" do
      s = session()
      {:ok, %{reservation: reservation, token: _token}} = Reservations.create(%{sessions: [s.id]})

      assert {:error, :not_found} = Reservations.fetch(reservation.id, "not-the-token")
      assert {:error, :not_found} = Reservations.fetch(Ecto.UUID.generate(), "token")
      assert {:error, :not_found} = Reservations.fetch(reservation.id, nil)
    end
  end

  describe "extend/2" do
    test "pushes expires_at forward and bumps last_activity_at" do
      s = session()
      {:ok, %{reservation: reservation, token: token}} = Reservations.create(%{sessions: [s.id]})

      assert {:ok, extended} = Reservations.extend(reservation.id, token)
      assert DateTime.compare(extended.expires_at, reservation.expires_at) == :gt
      assert DateTime.compare(extended.last_activity_at, reservation.last_activity_at) != :lt
      assert extended.status == :active
    end

    test "returns {:error, :expired} after the hold has lapsed" do
      s = session()
      {:ok, %{reservation: reservation, token: token}} = Reservations.create(%{sessions: [s.id]})

      expired = DateTime.add(DateTime.utc_now(), -60, :second)

      Repo.update_all(from(r in Reservation, where: r.id == ^reservation.id),
        set: [expires_at: expired]
      )

      assert {:error, :expired} = Reservations.extend(reservation.id, token)
    end
  end

  describe "release/2" do
    test "releases every held seat and marks the reservation :released" do
      s1 = session()
      s2 = session()

      {:ok, %{reservation: reservation, token: token}} =
        Reservations.create(%{sessions: [s1.id, s2.id]})

      assert :ok = Reservations.release(reservation.id, token)
      assert held_count(s1) == 0
      assert held_count(s2) == 0
      assert Repo.get!(Reservation, reservation.id).status == :released
      # Idempotent.
      assert :ok = Reservations.release(reservation.id, token)
    end
  end

  describe "expire_due/1" do
    test "releases seats and marks lapsed reservations :expired" do
      s = session()
      {:ok, %{reservation: reservation, token: _token}} = Reservations.create(%{sessions: [s.id]})
      assert held_count(s) == 1

      past = DateTime.add(DateTime.utc_now(), -60, :second)

      assert Reservations.expire_due(DateTime.utc_now()) == 0
      assert held_count(s) == 1

      assert Reservations.expire_due(DateTime.utc_now()) == 0

      Repo.update_all(from(r in Reservation, where: r.id == ^reservation.id),
        set: [expires_at: past]
      )

      assert Reservations.expire_due(DateTime.utc_now()) == 1
      assert held_count(s) == 0
      assert Repo.get!(Reservation, reservation.id).status == :expired

      # Idempotent.
      assert Reservations.expire_due(DateTime.utc_now()) == 0
    end
  end

  describe "convert/5" do
    test "books with credits and paid, sets the household, and does not double-count seats" do
      offering = insert(:offering, credit_cost: 1, drop_in_price: 2_500)
      venue = insert(:venue)
      s1 = session(offering_id: offering.id, venue_id: venue.id)
      s2 = session(offering_id: offering.id, venue_id: venue.id)

      household = Ecto.UUID.generate()
      credits_player = player(household)
      paid_player = player(household)
      {:ok, _} = Credits.grant_complimentary(nil, household, %{amount: 5})

      {:ok, %{reservation: reservation, token: token}} =
        Reservations.create(%{sessions: [s1.id, s2.id]})

      actor = actor(household)

      assert {0, 1} = occupancy(s1)
      assert {0, 1} = occupancy(s2)

      assignments = [
        %{session_id: s1.id, player_id: credits_player.id, method: :credits},
        %{session_id: s2.id, player_id: paid_player.id, method: :paid}
      ]

      assert {:ok, %{reservation: converted, bookings: bookings}} =
               Reservations.convert(reservation.id, token, actor, household, assignments)

      assert converted.status == :converted
      assert converted.household_id == household
      assert converted.converted_at != nil

      assert length(bookings) == 2
      assert bookings |> Enum.map(& &1.payment_method) |> Enum.sort() == [:credits, :paid]

      # Occupancy is unchanged: the guest hold was converted, not added.
      assert {1, 0} = occupancy(s1)
      assert {0, 1} = occupancy(s2)
      assert booked_count(s1) + held_count(s1) == 1
      assert booked_count(s2) + held_count(s2) == 1
    end

    test "a failed assignment rolls everything back: reservation active, seats still held" do
      offering = insert(:offering, credit_cost: 1)
      venue = insert(:venue)
      s1 = session(offering_id: offering.id, venue_id: venue.id)
      s2 = session(offering_id: offering.id, venue_id: venue.id)

      household = Ecto.UUID.generate()
      paid_player = player(household)
      credits_player = player(household)
      # No credits granted: the second assignment fails.

      {:ok, %{reservation: reservation, token: token}} =
        Reservations.create(%{sessions: [s1.id, s2.id]})

      actor = actor(household)

      assignments = [
        %{session_id: s1.id, player_id: paid_player.id, method: :paid},
        %{session_id: s2.id, player_id: credits_player.id, method: :credits}
      ]

      assert {:error, {:insufficient_credits, _message}} =
               Reservations.convert(reservation.id, token, actor, household, assignments)

      assert Repo.get!(Reservation, reservation.id).status == :active
      assert {0, 1} = occupancy(s1)
      assert {0, 1} = occupancy(s2)
      assert Repo.all(SportsCoachBookings.Bookings.Booking) == []
    end

    test "returns {:error, :reservation_expired} when the hold has lapsed" do
      offering = insert(:offering, credit_cost: 0)
      venue = insert(:venue)
      s = session(offering_id: offering.id, venue_id: venue.id)

      household = Ecto.UUID.generate()
      player = player(household)
      {:ok, _} = Credits.grant_complimentary(nil, household, %{amount: 5})

      {:ok, %{reservation: reservation, token: token}} = Reservations.create(%{sessions: [s.id]})

      past = DateTime.add(DateTime.utc_now(), -60, :second)

      Repo.update_all(from(r in Reservation, where: r.id == ^reservation.id),
        set: [expires_at: past]
      )

      assert {:error, :reservation_expired} =
               Reservations.convert(reservation.id, token, actor(household), household, [
                 %{session_id: s.id, player_id: player.id, method: :credits}
               ])

      assert Repo.get!(Reservation, reservation.id).status == :active
      assert held_count(s) == 1
    end
  end

  ## Helpers

  defp session(opts \\ []) do
    starts_at =
      DateTime.utc_now()
      |> DateTime.add(86_400, :second)
      |> DateTime.truncate(:microsecond)

    insert(
      :session,
      Keyword.merge(
        [
          capacity: 4,
          starts_at: starts_at,
          ends_at: DateTime.add(starts_at, 3600, :second)
        ],
        opts
      )
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
        phone: "+15555550100",
        priority: 1
      })

    player
  end

  defp actor(household) do
    CustomerActor.new(
      customer_user_id: Ecto.UUID.generate(),
      household_id: household,
      tenant_id: TenantContext.get_tenant_id()
    )
  end

  defp held_count(session), do: session |> reload() |> Map.fetch!(:held_count)
  defp booked_count(session), do: session |> reload() |> Map.fetch!(:booked_count)

  defp occupancy(session) do
    session = reload(session)
    {session.booked_count, session.held_count}
  end

  defp reload(session), do: Repo.get!(Session, session.id)
end
