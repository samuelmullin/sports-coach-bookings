defmodule SportsCoachBookings.Ops.ErrorReporter do
  @moduledoc """
  Error-reporting hook for crashes and background-job failures.

  Attaches to the telemetry events that represent a *failure*:

    * `[:phoenix, :router_dispatch, :exception]` — request handler raised
    * `[:phoenix, :endpoint, :stop]` with a non-2xx status is **not** used (too
      noisy); only exceptions are reported.
    * `[:oban, :job, :exception]` — a job exhausted its retries
    * `[:oban, :plugin, :exception]` — a plugin raised

  Every report is logged as a structured JSON error line (so it shows up in the
  Fly log drain) and, if configured, forwarded to a reporter module:

      # config/runtime.exs (production)
      config :sports_coach_bookings, :error_reporter, MySentryAdapter

  The adapter must implement `capture_exception/4`. Wiring an actual provider
  (Sentry/AppSignal) is a deploy-time concern; see `docs/ops.md`. The default
  (`nil`) logs only, so the app never hard-depends on an error tracker.
  """

  use GenServer

  require Logger

  @handler_id "sports-coach-bookings-error-reporter"

  @events [
    [:phoenix, :router_dispatch, :exception],
    [:oban, :job, :exception],
    [:oban, :plugin, :exception]
  ]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    :telemetry.attach_many(@handler_id, @events, &__MODULE__.handle_event/4, nil)
    {:ok, %{}}
  end

  @doc false
  def handle_event(event, measurements, metadata, _config) do
    kind =
      metadata[:kind] ||
        (is_map(metadata[:reason]) && metadata[:reason].__struct__) ||
        :error

    reason = metadata[:reason] || metadata[:error]
    stacktrace = metadata[:stacktrace] || []

    Logger.error(
      "unhandled error",
      error: %{
        event: Enum.join(event, "."),
        kind: inspect(kind),
        reason: inspect(reason),
        duration: measurements[:duration]
      }
    )

    report(event, kind, reason, stacktrace, metadata)

    :ok
  end

  defp report(event, kind, reason, stacktrace, metadata) do
    case Application.get_env(:sports_coach_bookings, :error_reporter) do
      nil ->
        :ok

      module when is_atom(module) ->
        if function_exported?(module, :capture_exception, 4) do
          module.capture_exception(kind, reason, stacktrace, Map.put(metadata, :event, event))
        else
          Logger.warning(
            "configured :error_reporter #{inspect(module)} does not export capture_exception/4"
          )
        end
    end

    :ok
  end
end
