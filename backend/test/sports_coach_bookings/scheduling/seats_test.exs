defmodule SportsCoachBookings.Scheduling.SeatsTest do
  use SportsCoachBookings.DataCase, async: false

  alias SportsCoachBookings.Core.TenantContext
  alias SportsCoachBookings.Scheduling.Seats
  alias SportsCoachBookings.Scheduling.Session

  setup do
    tenant = insert(:tenant)
    put_tenant(tenant)
    %{tenant: tenant}
  end

  defp insert_session(capacity) do
    insert(:session,
      tenant_id: TenantContext.get_tenant_id(),
      capacity: capacity,
      starts_at: DateTime.utc_now() |> DateTime.add(1, :day) |> DateTime.truncate(:microsecond)
    )
  end

  test "concurrent holds never oversell capacity" do
    # The SQL sandbox serialises statements onto one connection, so true OS
    # parallelism is not observable here. We still hammer the exact atomic path
    # wp-14 uses — a transaction that locks the row and updates the counters —
    # and assert the invariant holds across all attempts: exactly `capacity`
    # holds succeed and every other attempt is rejected with :capacity_exceeded.
    capacity = 5
    session = insert_session(capacity)
    attempts = 25

    results =
      for _ <- 1..attempts do
        Repo.with_tenant_tx(fn ->
          with {:ok, locked} <- lock(session.id) do
            Seats.adjust!(locked, 0, 1)
          end
        end)
      end

    successes = Enum.count(results, &match?({:ok, {:ok, _session}}, &1))
    rejected = Enum.count(results, &match?({:ok, {:error, :capacity_exceeded}}, &1))

    assert successes == capacity
    assert rejected == attempts - capacity

    fresh = Repo.get!(Session, session.id)
    assert fresh.held_count == capacity
    assert fresh.booked_count + fresh.held_count <= fresh.capacity

    assert {:ok, {:error, :capacity_exceeded}} =
             Repo.with_tenant_tx(fn ->
               locked = Seats.lock_session!(session.id)
               Seats.adjust!(locked, 0, 1)
             end)
  end

  test "confirm_hold moves held to booked and release_booking frees the seat" do
    session = insert_session(2)

    assert {:ok, {:ok, held}} =
             Repo.with_tenant_tx(fn -> Seats.hold(session.id) end)

    assert {held.booked_count, held.held_count} == {0, 1}

    assert {:ok, {:ok, confirmed}} =
             Repo.with_tenant_tx(fn -> Seats.confirm_hold(session.id) end)

    assert {confirmed.booked_count, confirmed.held_count} == {1, 0}

    assert {:ok, {:ok, released}} =
             Repo.with_tenant_tx(fn -> Seats.release_booking(session.id) end)

    assert {released.booked_count, released.held_count} == {0, 0}
  end

  test "the database check constraint is the final backstop" do
    session = insert_session(1)

    assert {:ok, _} = Repo.with_tenant_tx(fn -> Seats.hold(session.id) end)

    # Bypass the guard with a direct write: Postgres rejects it.
    assert_raise Postgrex.Error, fn ->
      Repo.with_tenant_tx(fn ->
        Repo.update_all(
          from(s in Session, where: s.id == ^session.id),
          set: [held_count: 2]
        )
      end)
    end
  end

  test "lock_session! raises for a missing session" do
    assert_raise Ecto.NoResultsError, fn ->
      Repo.with_tenant_tx(fn -> Seats.lock_session!(Ecto.UUID.generate()) end)
    end
  end

  defp lock(session_id) do
    {:ok, Seats.lock_session!(session_id)}
  rescue
    Ecto.NoResultsError -> {:error, :not_found}
  end
end
