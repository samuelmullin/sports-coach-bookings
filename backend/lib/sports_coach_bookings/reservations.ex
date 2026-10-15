defmodule SportsCoachBookings.Reservations do
  @moduledoc """
  Guest reservations: short-lived holds on session seats for an anonymous
  visitor, converted to real bookings after they authenticate. Owned by the
  Reservations context.

  A visitor selects one or more sessions; the context holds one seat per session
  through `SportsCoachBookings.Scheduling.Seats` (the only writer of
  `booked_count`/`held_count`) and returns an opaque bearer token. Only the
  token's SHA-256 hash is stored. The hold lasts 10 minutes and can be
  extended or released; a platform sweeper (`expire_due/1`) releases holds that
  lapse, so `confirmed + held <= capacity` (invariant 2) always holds.

  Every write runs inside `SportsCoachBookings.Repo.with_tenant_tx/2` (RLS).

  ## `expire_due/1` and `skip_tenant`

  The sweeper runs from a platform-level cron job with no tenant in context. It
  cannot scan `reservations` across tenants with `skip_tenant: true`: RLS is
  forced on every tenant-owned table, so a query without `app.tenant_id` set
  matches no rows (see `docs/rfcs/20260929-reservations-guest-holds.md`). It
  therefore enumerates active tenants from the platform `tenants` table and
  sweeps each tenant inside `TenantContext.with_tenant/2`, exactly like
  `SportsCoachBookings.Credits.DispatchExpiryWorker`.
  """

  import Ecto.Query

  alias SportsCoachBookings.Bookings
  alias SportsCoachBookings.Core.Tenant
  alias SportsCoachBookings.Core.TenantContext
  alias SportsCoachBookings.Repo
  alias SportsCoachBookings.Reservations.Reservation
  alias SportsCoachBookings.Reservations.ReservationSession
  alias SportsCoachBookings.Scheduling
  alias SportsCoachBookings.Scheduling.Seats

  @ttl_minutes 10

  ## Create

  @doc """
  Creates a guest reservation holding one seat in each of `attrs[:sessions]`.

  `attrs` accepts `:sessions` (a non-empty list of session ids) and an optional
  `:offering_id`. Holds are taken inside a single transaction: if any session is
  full or missing, the whole reservation is rolled back (no partial holds) and
  `{:error, {:session_full, id}}` or `{:error, {:invalid_session, id}}` is
  returned. On success returns `{:ok, %{reservation: reservation, token: token}}`
  where `token` is the only time the opaque token is exposed.
  """
  @spec create(map() | keyword()) ::
          {:ok, %{reservation: Reservation.t(), token: binary()}} | {:error, term()}
  def create(attrs) do
    attrs = normalize(attrs)

    sessions =
      attrs |> get_attr(:sessions) |> List.wrap() |> Enum.reject(&is_nil/1) |> Enum.uniq()

    offering_id = get_attr(attrs, :offering_id)
    token = generate_token()
    token_hash = hash_token(token)
    now = now()

    write(fn -> do_create(sessions, offering_id, token, token_hash, now) end)
  end

  defp do_create(sessions, offering_id, token, token_hash, now) do
    if sessions == [] do
      Repo.rollback({:invalid_sessions, "At least one session is required"})
    end

    Enum.each(sessions, fn session_id ->
      case Seats.hold(session_id, 1) do
        {:ok, _session} -> :ok
        {:error, :capacity_exceeded} -> Repo.rollback({:session_full, session_id})
        {:error, _reason} -> Repo.rollback({:invalid_session, session_id})
      end
    end)

    reservation =
      %Reservation{}
      |> Reservation.create_changeset(%{
        tenant_id: TenantContext.get_tenant_id(),
        token_hash: token_hash,
        offering_id: offering_id,
        status: :active,
        expires_at: DateTime.add(now, @ttl_minutes, :minute),
        last_activity_at: now
      })
      |> Repo.insert!()

    Enum.each(sessions, fn session_id ->
      %ReservationSession{}
      |> ReservationSession.changeset(%{
        tenant_id: reservation.tenant_id,
        reservation_id: reservation.id,
        session_id: session_id
      })
      |> Repo.insert!()
    end)

    {:ok, %{reservation: hydrate(reservation), token: token}}
  end

  ## Reads

  @doc """
  Fetches a reservation by id when `token` matches its stored hash.

  Returns `{:ok, reservation}` (with `session_summaries` populated) regardless of
  status, or `{:error, :not_found}` for a bad id or token.
  """
  @spec fetch(binary(), binary() | nil) :: {:ok, Reservation.t()} | {:error, :not_found}
  def fetch(id, token) when is_binary(id) do
    write(fn ->
      case fetch_authorized(id, token) do
        {:ok, reservation} -> {:ok, hydrate(reservation)}
        {:error, reason} -> {:error, reason}
      end
    end)
  end

  ## Extend / release

  @doc """
  Extends an active reservation by another #{@ttl_minutes} minutes.

  Returns `{:ok, reservation}` or `{:error, :expired}` when the reservation is
  no longer active (including when it has lapsed but has not yet been swept).
  """
  @spec extend(binary(), binary() | nil) :: {:ok, Reservation.t()} | {:error, term()}
  def extend(id, token) when is_binary(id) do
    write(fn -> do_extend(id, token) end)
  end

  defp do_extend(id, token) do
    case lock_authorized(id, token) do
      {:ok, %Reservation{status: :active} = reservation} ->
        now = now()

        if expired?(reservation, now) do
          {:error, :expired}
        else
          updated =
            reservation
            |> Reservation.update_changeset(%{
              expires_at: DateTime.add(now, @ttl_minutes, :minute),
              last_activity_at: now
            })
            |> Repo.update!()

          {:ok, hydrate(updated)}
        end

      {:ok, %Reservation{}} ->
        {:error, :expired}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Releases every seat held by an active reservation and marks it `:released`.

  Idempotent for an already-released reservation. Returns `:ok` or an error.
  """
  @spec release(binary(), binary() | nil) :: :ok | {:error, term()}
  def release(id, token) when is_binary(id) do
    write(fn ->
      case lock_authorized(id, token) do
        {:ok, %Reservation{status: :active} = reservation} ->
          release_holds(reservation)

          reservation
          |> Reservation.update_changeset(%{status: :released})
          |> Repo.update!()

          :ok

        {:ok, %Reservation{status: :released}} ->
          :ok

        {:ok, %Reservation{}} ->
          {:error, :not_active}

        {:error, reason} ->
          {:error, reason}
      end
    end)
  end

  ## Sweeper

  @doc """
  Releases the seats of every active reservation whose hold has lapsed and marks
  it `:expired`. Platform-level: fans out per active tenant. Idempotent. Returns
  the number of reservations expired.
  """
  @spec expire_due(DateTime.t()) :: non_neg_integer()
  def expire_due(now \\ DateTime.utc_now()) do
    now = truncate(now)

    Tenant
    |> where([t], t.status == :active)
    |> select([t], t.id)
    |> Repo.all()
    |> Enum.reduce(0, fn tenant_id, acc ->
      acc + TenantContext.with_tenant(tenant_id, fn -> expire_for_tenant(now) end)
    end)
  end

  ## Convert

  @doc """
  Converts an active reservation into real bookings after the visitor signs up.

  `assignments` is a list of `%{session_id: id, player_id: id, method: :credits | :paid}`.
  Every guest hold is first released (so sessions without an assignment do not
  leak a seat), then `Bookings.book/4` is called per assignment inside the same
  transaction. Any failure rolls the whole thing back — the reservation stays
  `:active` and the seats stay held.

  Returns `{:ok, %{reservation: reservation, bookings: [Booking.t()]}}`, or
  `{:error, :reservation_expired}` when the reservation is not active or has
  lapsed, or the booking error otherwise.
  """
  @spec convert(binary(), binary() | nil, term(), binary(), [map()]) ::
          {:ok, %{reservation: Reservation.t(), bookings: [term()]}} | {:error, term()}
  def convert(id, token, actor, household_id, assignments) when is_binary(id) do
    assignments = normalize_assignments(assignments)

    write(fn -> perform_convert(id, token, actor, household_id, assignments) end)
  end

  defp perform_convert(id, token, actor, household_id, assignments) do
    case lock_authorized(id, token) do
      {:ok, reservation} ->
        now = now()

        cond do
          reservation.status != :active -> Repo.rollback(:reservation_expired)
          expired?(reservation, now) -> Repo.rollback(:reservation_expired)
          true -> do_convert(reservation, actor, household_id, assignments, now)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  ## Serialisation

  @doc """
  Serialises a reservation for the API.

  Returns `id`, `status`, `expires_at`, `last_activity_at`, `offering_id`, and
  `sessions: [%{session_id, starts_at, ends_at}]`.
  """
  @spec serialize(Reservation.t()) :: map()
  def serialize(%Reservation{} = reservation) do
    %{
      id: reservation.id,
      status: to_string(reservation.status),
      expires_at: reservation.expires_at,
      last_activity_at: reservation.last_activity_at,
      offering_id: reservation.offering_id,
      sessions: reservation.session_summaries || []
    }
  end

  ## Convert internals

  defp do_convert(reservation, actor, household_id, assignments, now) do
    reservation = Repo.preload(reservation, :reservation_sessions)
    reserved_ids = Enum.map(reservation.reservation_sessions, & &1.session_id)

    Enum.each(assignments, fn %{session_id: session_id} ->
      unless session_id in reserved_ids do
        Repo.rollback({:invalid_session, session_id})
      end
    end)

    release_holds(reservation)

    bookings =
      Enum.map(assignments, fn %{session_id: session_id, player_id: player_id, method: method} ->
        case Bookings.book(actor, player_id, session_id, method) do
          {:ok, booking} -> booking
          {:error, reason} -> Repo.rollback(reason)
        end
      end)

    updated =
      reservation
      |> Reservation.update_changeset(%{
        status: :converted,
        household_id: household_id,
        converted_at: now
      })
      |> Repo.update!()

    {:ok, %{reservation: hydrate(updated), bookings: bookings}}
  end

  ## Sweeper internals

  defp expire_for_tenant(now) do
    case write(fn ->
           ids =
             Repo.all(
               from r in Reservation,
                 where: r.status == :active and r.expires_at < ^now,
                 order_by: [asc: r.expires_at, asc: r.id],
                 select: r.id
             )

           Enum.each(ids, &expire_one/1)
           {:ok, length(ids)}
         end) do
      {:ok, count} -> count
      _ -> 0
    end
  end

  defp expire_one(id) do
    case Repo.one(from r in Reservation, where: r.id == ^id, lock: "FOR UPDATE") do
      %Reservation{status: :active} = reservation ->
        release_holds(reservation)

        reservation
        |> Reservation.update_changeset(%{status: :expired})
        |> Repo.update!()

        :ok

      _ ->
        :ok
    end
  end

  defp release_holds(reservation) do
    reservation = Repo.preload(reservation, :reservation_sessions)

    Enum.each(reservation.reservation_sessions, fn reservation_session ->
      case Seats.release_hold(reservation_session.session_id, 1) do
        {:ok, _session} -> :ok
        {:error, :negative_count} -> :ok
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  ## Lookup helpers

  defp fetch_authorized(id, token) do
    with %Reservation{} = reservation <- Repo.get(Reservation, id),
         true <- valid_token?(reservation, token) do
      {:ok, reservation}
    else
      _ -> {:error, :not_found}
    end
  end

  defp lock_authorized(id, token) do
    case Repo.one(from r in Reservation, where: r.id == ^id, lock: "FOR UPDATE") do
      nil ->
        {:error, :not_found}

      %Reservation{} = reservation ->
        if valid_token?(reservation, token) do
          {:ok, reservation}
        else
          {:error, :not_found}
        end
    end
  end

  defp hydrate(%Reservation{} = reservation) do
    reservation = Repo.preload(reservation, :reservation_sessions)

    summaries =
      Enum.map(reservation.reservation_sessions, fn reservation_session ->
        case Scheduling.fetch_session(reservation_session.session_id) do
          {:ok, session} ->
            %{session_id: session.id, starts_at: session.starts_at, ends_at: session.ends_at}

          {:error, _reason} ->
            %{session_id: reservation_session.session_id, starts_at: nil, ends_at: nil}
        end
      end)

    %{reservation | session_summaries: summaries}
  end

  ## Token helpers

  defp generate_token, do: Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)

  defp hash_token(token) when is_binary(token), do: :crypto.hash(:sha256, token)

  defp valid_token?(_reservation, token) when not is_binary(token), do: false

  defp valid_token?(%Reservation{token_hash: token_hash}, token) when is_binary(token_hash) do
    :crypto.hash_equals(token_hash, hash_token(token))
  end

  defp valid_token?(_reservation, _token), do: false

  ## Shared helpers

  defp expired?(%Reservation{expires_at: expires_at}, now) do
    DateTime.compare(expires_at, now) == :lt
  end

  defp normalize_assignments(assignments) when is_list(assignments) do
    Enum.map(assignments, fn
      %{session_id: session_id, player_id: player_id} = assignment ->
        %{
          session_id: session_id,
          player_id: player_id,
          method: normalize_method(Map.get(assignment, :method))
        }

      %{"session_id" => session_id, "player_id" => player_id} = assignment ->
        %{
          session_id: session_id,
          player_id: player_id,
          method: normalize_method(Map.get(assignment, "method"))
        }
    end)
  end

  defp normalize_assignments(_assignments), do: []

  defp normalize_method(method) when method in [:credits, :paid], do: method
  defp normalize_method("credits"), do: :credits
  defp normalize_method("paid"), do: :paid
  defp normalize_method(other), do: other

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:microsecond)

  defp truncate(%DateTime{} = value), do: DateTime.truncate(value, :microsecond)

  defp normalize(attrs), do: Enum.into(attrs, %{})

  defp get_attr(attrs, key), do: Map.get(attrs, key) || Map.get(attrs, to_string(key))

  ## Privacy erasure

  @doc "Deletes a household's reservation holds. Called by `SportsCoachBookings.Privacy`."
  @spec erase_household(binary()) :: non_neg_integer()
  def erase_household(household_id) do
    write(fn ->
      {count, _} = Repo.delete_all(from r in Reservation, where: r.household_id == ^household_id)
      count
    end)
  end

  defp write(fun) do
    case Repo.with_tenant_tx(fun) do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end
end
