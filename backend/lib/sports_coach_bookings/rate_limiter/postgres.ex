defmodule SportsCoachBookings.RateLimiter.Postgres do
  @moduledoc """
  Postgres backend for `SportsCoachBookings.RateLimiter`: fixed-window counters
  shared by every machine, so the effective limit does not multiply with the
  fleet size.

  Each hit is one atomic `INSERT ... ON CONFLICT DO UPDATE` that either starts a
  new window or increments the current one, using the **database clock** so
  machines with skewed clocks agree. Backed by the `rate_limit_counters`
  UNLOGGED table. Only rate-limited (low-volume) endpoints pay the round trip.

  Failures **fail open**: if the database errors the request is allowed and the
  error is logged, because the same outage already breaks the endpoints being
  protected.
  """

  require Logger

  alias SportsCoachBookings.Repo

  @upsert """
  INSERT INTO rate_limit_counters AS c (key, count, window_started_at)
  VALUES ($1, 1, clock_timestamp())
  ON CONFLICT (key) DO UPDATE SET
    count = CASE
      WHEN c.window_started_at <= clock_timestamp() - make_interval(secs => $2::int)
      THEN 1 ELSE c.count + 1 END,
    window_started_at = CASE
      WHEN c.window_started_at <= clock_timestamp() - make_interval(secs => $2::int)
      THEN clock_timestamp() ELSE c.window_started_at END
  RETURNING
    c.count,
    EXTRACT(EPOCH FROM (c.window_started_at + make_interval(secs => $2::int) - clock_timestamp()))::float8
  """

  @doc """
  Records a hit on `key`. Returns `:ok` or `{:error, retry_after_ms}`.
  """
  @spec check(binary(), pos_integer(), pos_integer()) :: :ok | {:error, pos_integer()}
  def check(key, limit, window_seconds) do
    case Repo.query(@upsert, [key, window_seconds], skip_tenant: true) do
      {:ok, %{rows: [[count, _remaining]]}} when count <= limit ->
        :ok

      {:ok, %{rows: [[_count, remaining_seconds]]}} ->
        {:error, max(1, ceil(remaining_seconds * 1_000))}

      {:error, error} ->
        fail_open(error)
    end
  rescue
    error -> fail_open(error)
  end

  @doc "Deletes counters whose window started more than `older_than_seconds` ago."
  @spec prune(pos_integer()) :: non_neg_integer()
  def prune(older_than_seconds) do
    sql =
      "DELETE FROM rate_limit_counters " <>
        "WHERE window_started_at < clock_timestamp() - make_interval(secs => $1::int)"

    case Repo.query(sql, [older_than_seconds], skip_tenant: true) do
      {:ok, %{num_rows: count}} -> count
      {:error, _} -> 0
    end
  rescue
    _ -> 0
  end

  @doc "Deletes every counter. Used by tests."
  @spec reset() :: :ok
  def reset do
    Repo.query!("DELETE FROM rate_limit_counters", [], skip_tenant: true)
    :ok
  end

  defp fail_open(error) do
    Logger.error("[rate_limiter] postgres backend failed, allowing request: #{inspect(error)}")
    :ok
  end
end
