defmodule SportsCoachBookings.RateLimiter do
  @moduledoc """
  An exact sliding-window rate limiter (WP-19) with two interchangeable backends,
  chosen by `config :sports_coach_bookings, :rate_limit_backend`:

    * `:ets` (default; dev/test) — in-process hit histories, **per node**. With N
      machines the effective limit is N times higher and resets independently.
    * `:postgres` (production default, see `config/runtime.exs`) — hit histories
      in the `rate_limit_events` table via
      `SportsCoachBookings.RateLimiter.Postgres`, shared by every machine.

  Histories are keyed by an arbitrary binary (the plug builds keys such as
  `"ip:203.0.113.4"` and `"acct:user@example.com"`). A request is allowed only
  when **every** key is under its limit. Unlike a fixed window, the limiter
  cannot admit a double burst across an arbitrary clock boundary. Stale hits
  are pruned by the owning process.
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
    result = check(backend(), Enum.uniq(keys), window_seconds * 1_000, limit)

    case result do
      :ok -> :ok
      {:error, retry_after_ms} -> {:error, max(1, div(retry_after_ms, 1_000))}
    end
  end

  @doc "Clears all counters. Used by tests."
  @spec reset() :: :ok
  def reset do
    if :ets.whereis(@table) != :undefined, do: :ets.delete_all_objects(@table)
    if backend() == :postgres, do: Postgres.reset()
    :ok
  end

  @doc "Deletes ETS hit histories whose newest hit is before `cutoff_ms`."
  @spec prune(integer()) :: non_neg_integer()
  def prune(cutoff_ms) do
    @table
    |> :ets.tab2list()
    |> Enum.count(fn
      {key, [newest | _]} when newest < cutoff_ms -> :ets.delete(@table, key)
      _ -> false
    end)
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

  defp check(:postgres, keys, window_ms, limit),
    do: Postgres.check_many(keys, limit, div(window_ms, 1_000))

  defp check(:ets, keys, window_ms, limit),
    do:
      GenServer.call(
        __MODULE__,
        {:check_many, keys, System.monotonic_time(:millisecond), window_ms, limit}
      )

  @impl true
  def handle_call({:check_many, keys, now, window_ms, limit}, _from, state) do
    cutoff = now - window_ms

    histories =
      Map.new(keys, fn key ->
        hits =
          case :ets.lookup(@table, key) do
            [{^key, existing}] -> Enum.take_while(existing, &(&1 > cutoff))
            [] -> []
          end

        :ets.insert(@table, {key, hits})
        {key, hits}
      end)

    retries =
      for {_key, hits} <- histories,
          length(hits) >= limit,
          oldest = List.last(hits),
          do: max(1, oldest + window_ms - now)

    case retries do
      [] ->
        Enum.each(histories, fn {key, hits} -> :ets.insert(@table, {key, [now | hits]}) end)
        {:reply, :ok, state}

      values ->
        {:reply, {:error, Enum.max(values)}, state}
    end
  end

  defp schedule_prune, do: Process.send_after(self(), :prune, @prune_interval_ms)
end
