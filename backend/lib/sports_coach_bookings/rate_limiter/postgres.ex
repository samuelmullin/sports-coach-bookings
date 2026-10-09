defmodule SportsCoachBookings.RateLimiter.Postgres do
  @moduledoc """
  Postgres backend for `SportsCoachBookings.RateLimiter`: exact sliding-window hits
  shared by every machine, so the effective limit does not multiply with the
  fleet size.

  Each key is serialized with a transaction-scoped advisory lock, expired hits
  are deleted, and the current window is counted using the **database clock**
  so machines with skewed clocks agree. Backed by the `rate_limit_events`
  UNLOGGED table. Only rate-limited (low-volume) endpoints pay these queries.

  Failures fail closed for the affected request with a short retry interval and
  are logged. This keeps an infrastructure fault from silently disabling an
  abuse control.
  """

  require Logger

  alias SportsCoachBookings.Repo

  @doc """
  Records a hit on `key`. Returns `:ok` or `{:error, retry_after_ms}`.
  """
  @spec check(binary(), pos_integer(), pos_integer()) :: :ok | {:error, pos_integer()}
  def check(key, limit, window_seconds) do
    check_many([key], limit, window_seconds)
  end

  @doc "Atomically records a hit on every key, or records none when any key is full."
  @spec check_many([binary()], pos_integer(), pos_integer()) :: :ok | {:error, pos_integer()}
  def check_many(keys, limit, window_seconds) do
    case Repo.transaction(fn -> check_many_locked(keys, limit, window_seconds) end) do
      {:ok, result} -> result
      {:error, error} -> fail_closed(error)
    end
  rescue
    error -> fail_closed(error)
  end

  @doc "Deletes hits older than `older_than_seconds`."
  @spec prune(pos_integer()) :: non_neg_integer()
  def prune(older_than_seconds) do
    case Repo.query(
           "DELETE FROM rate_limit_events " <>
             "WHERE hit_at < clock_timestamp() - make_interval(secs => $1::int)",
           [older_than_seconds],
           skip_tenant: true
         ) do
      {:ok, %{num_rows: count}} -> count
      {:error, _} -> 0
    end
  rescue
    _ -> 0
  end

  @doc "Deletes every hit. Used by tests."
  @spec reset() :: :ok
  def reset do
    Repo.query!("DELETE FROM rate_limit_events", [], skip_tenant: true)
    :ok
  end

  defp check_many_locked(keys, limit, window_seconds) do
    keys = keys |> Enum.uniq() |> Enum.sort()

    Enum.each(keys, fn key ->
      Repo.query!("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", [key],
        skip_tenant: true
      )
    end)

    %{rows: [[now]]} = Repo.query!("SELECT clock_timestamp()", [], skip_tenant: true)

    histories = Map.new(keys, &{&1, history(&1, now, window_seconds)})

    retries =
      for {_key, {count, oldest}} <- histories,
          count >= limit,
          do: max(1, DateTime.diff(oldest, now, :millisecond) + window_seconds * 1_000)

    case retries do
      [] ->
        Enum.each(keys, fn key ->
          Repo.query!("INSERT INTO rate_limit_events (key, hit_at) VALUES ($1, $2)", [key, now],
            skip_tenant: true
          )
        end)

        :ok

      values ->
        {:error, Enum.max(values)}
    end
  end

  defp history(key, now, window_seconds) do
    Repo.query!(
      "DELETE FROM rate_limit_events " <>
        "WHERE key = $1 AND hit_at <= $2::timestamptz - make_interval(secs => $3::int)",
      [key, now, window_seconds],
      skip_tenant: true
    )

    %{rows: [[count, oldest]]} =
      Repo.query!(
        "SELECT count(*)::int, min(hit_at) FROM rate_limit_events WHERE key = $1",
        [key],
        skip_tenant: true
      )

    {count, oldest}
  end

  defp fail_closed(error) do
    Logger.error("[rate_limiter] postgres backend failed, denying request: #{inspect(error)}")
    {:error, 1_000}
  end
end
