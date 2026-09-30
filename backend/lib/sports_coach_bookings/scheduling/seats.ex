defmodule SportsCoachBookings.Scheduling.Seats do
  @moduledoc """
  The only writer of `sessions.booked_count` / `sessions.held_count` (wp-14 uses
  this module). Owned by wp-11.

  The pattern is: lock the session row with `lock_session!/1` **inside the
  caller's transaction**, then move the counters with `adjust!/3`. The row lock
  serialises concurrent bookings so that
  `booked_count + held_count <= capacity` (invariant 2) always holds; the
  database check constraint is the final backstop.

      Repo.with_tenant_tx(fn ->
        session = Seats.lock_session!(session_id)
        Seats.adjust!(session, +1, +1) # confirm one seat held by this booking
      end)

  The convenience functions `hold/2`, `confirm_hold/2`, `release_hold/2`, and
  `release_booking/2` each lock and adjust in one call and must also run inside a
  transaction with the tenant in context.
  """

  import Ecto.Query

  alias SportsCoachBookings.Repo
  alias SportsCoachBookings.Scheduling.Session

  @doc """
  Locks the session row `FOR UPDATE` in the caller's transaction and returns it
  with current `booked_count` / `held_count`.

  Raises `Ecto.NoResultsError` when the session does not exist (or is not visible
  under the tenant's RLS).
  """
  @spec lock_session!(binary()) :: Session.t()
  def lock_session!(session_id) do
    Repo.one!(
      from s in Session,
        where: s.id == ^session_id,
        lock: "FOR UPDATE"
    )
  end

  @doc """
  Applies signed deltas to a session that is already locked by the caller.

  Returns `{:error, :negative_count}` for a negative resulting counter,
  `{:error, :capacity_exceeded}` when the result would exceed capacity, and
  `{:error, :not_found}` when the row disappeared.
  """
  @spec adjust!(Session.t(), integer(), integer()) ::
          {:ok, Session.t()} | {:error, atom()}
  def adjust!(%Session{} = session, booked_delta, held_delta)
      when is_integer(booked_delta) and is_integer(held_delta) do
    booked = session.booked_count + booked_delta
    held = session.held_count + held_delta

    cond do
      booked < 0 or held < 0 ->
        {:error, :negative_count}

      booked + held > session.capacity ->
        {:error, :capacity_exceeded}

      true ->
        now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

        {count, rows} =
          Repo.update_all(
            from(s in Session,
              where: s.id == ^session.id,
              select: s
            ),
            set: [booked_count: booked, held_count: held, updated_at: now]
          )

        case {count, rows} do
          {1, [updated]} -> {:ok, updated}
          _ -> {:error, :not_found}
        end
    end
  end

  @doc "Holds `count` seats (creation of a pending booking). Must run in a transaction."
  @spec hold(binary(), pos_integer()) :: {:ok, Session.t()} | {:error, atom()}
  def hold(session_id, count \\ 1), do: lock_and_adjust(session_id, 0, count)

  @doc """
  Confirms `count` previously held seats (held → confirmed). Must run in a
  transaction.
  """
  @spec confirm_hold(binary(), pos_integer()) :: {:ok, Session.t()} | {:error, atom()}
  def confirm_hold(session_id, count \\ 1), do: lock_and_adjust(session_id, count, -count)

  @doc "Releases `count` held seats (a hold expired or was abandoned)."
  @spec release_hold(binary(), pos_integer()) :: {:ok, Session.t()} | {:error, atom()}
  def release_hold(session_id, count \\ 1), do: lock_and_adjust(session_id, 0, -count)

  @doc "Releases `count` confirmed seats (a booking was cancelled)."
  @spec release_booking(binary(), pos_integer()) :: {:ok, Session.t()} | {:error, atom()}
  def release_booking(session_id, count \\ 1), do: lock_and_adjust(session_id, -count, 0)

  defp lock_and_adjust(session_id, booked_delta, held_delta) do
    case Repo.one(from s in Session, where: s.id == ^session_id, lock: "FOR UPDATE") do
      nil -> {:error, :not_found}
      session -> adjust!(session, booked_delta, held_delta)
    end
  end
end
