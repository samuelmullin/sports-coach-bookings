defmodule SportsCoachBookings.RateLimiter do
  @moduledoc """
  A small fixed-window rate limiter (WP-19) with two interchangeable backends,
  chosen by `config :sports_coach_bookings, :rate_limit_backend`:

    * `:ets` (default; dev/test) — in-process counters, **per node**. With N
      machines the effective limit is N times higher and resets independently.
    * `:postgres` (production default, see `config/runtime.exs`) — counters in
      the `rate_limit_counters` table via
      `SportsCoachBookings.RateLimiter.Postgres`, shared by every machine.

  Counters are keyed by an arbitrary binary (the plug builds keys such as
  `"ip:203.0.113.4"` and `"acct:user@example.com"`). A request is allowed only
  when **every** key is under its limit. Stale windows are pruned by the
  owning process.
  """

  use GenServer

  alias SportsCoachBookings.RateLimiter.Postgres

  @table __MODULE__
  @prune_interval_ms 60_000
  # Entries older than this are always stale relative to the longest window the
  # app uses (signup: 3600s).
  @max_window_ms 4 * 60 * 60 * 1_000

  @doc "Starts the limiter and creates its ETS table."
  @spec start_link(term()) :: GenServer.on_start()
  def start_link(_opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @doc "The active backend: `:ets` or `:postgres`."
  @spec backend() :: :ets | :postgres
  def backend, do: Application.get_env(:sports_coach_bookings, :rate_limit_backend, :ets)

  @doc "Whether enforcement is enabled (config: `:rate_limiting_enabled`)."
  @spec enabled?() :: boolean()
  def enabled? do
    Application.get_env(:sports_coach_bookings, :rate_limiting_enabled, true)
  end

  @doc """
  Records one hit against each key in `keys`.

  Returns `:ok` when all keys are within their limit, or `{:error, retry_after}`
  (seconds) when any key has exceeded it. `limit` is the maximum number of hits
  allowed per `window_seconds` window.
  """
  @spec hit([binary()], pos_integer(), pos_integer()) :: :ok | {:error, pos_integer()}
  def hit(keys, limit, window_seconds)
      when is_list(keys) and is_integer(limit) and limit > 0 and is_integer(window_seconds) and
             window_seconds > 0 do
    now = System.monotonic_time(:millisecond)
    window_ms = window_seconds * 1_000

    Enum.reduce(keys, :ok, fn key, acc ->
      case check(backend(), key, now, window_ms, limit) do
        :ok -> acc
        {:error, retry_after_ms} -> merge_deny(acc, retry_after_ms)
      end
    end)
  end

  @doc "Clears all counters. Used by tests."
  @spec reset() :: :ok
  def reset do
    if :ets.whereis(@table) != :undefined, do: :ets.delete_all_objects(@table)
    if backend() == :postgres, do: Postgres.reset()
    :ok
  end

  @doc "Deletes counters whose window started before `cutoff_ms`."
  @spec prune(integer()) :: non_neg_integer()
  def prune(cutoff_ms) do
    :ets.select_delete(@table, [{{:"$1", :"$2", :"$3"}, [{:<, :"$3", cutoff_ms}], [true]}])
  end

  ## GenServer

  @impl true
  def init(:ok) do
    :ets.new(@table, [
      :named_table,
      :public,
      :set,
      write_concurrency: true,
      read_concurrency: true
    ])

    schedule_prune()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:prune, state) do
    prune(System.monotonic_time(:millisecond) - @max_window_ms)
    if backend() == :postgres, do: Postgres.prune(div(@max_window_ms, 1_000))
    schedule_prune()
    {:noreply, state}
  end

  def handle_info(_message, state), do: {:noreply, state}

  ## Internals

  defp check(:postgres, key, _now, window_ms, limit),
    do: Postgres.check(key, limit, div(window_ms, 1_000))

  defp check(:ets, key, now, window_ms, limit) do
    case :ets.lookup(@table, key) do
      [{^key, _count, started_at}] when now - started_at < window_ms ->
        new = :ets.update_counter(@table, key, {2, 1})

        if new > limit do
          {:error, window_ms - (now - started_at)}
        else
          :ok
        end

      _ ->
        :ets.insert(@table, {key, 1, now})
        :ok
    end
  end

  defp merge_deny(:ok, retry_after_ms), do: {:error, max(1, div(retry_after_ms, 1_000))}

  defp merge_deny({:error, existing}, retry_after_ms),
    do: {:error, max(existing, max(1, div(retry_after_ms, 1_000)))}

  defp schedule_prune, do: Process.send_after(self(), :prune, @prune_interval_ms)
end
