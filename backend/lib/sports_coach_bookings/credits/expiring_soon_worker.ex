defmodule SportsCoachBookings.Credits.ExpiringSoonWorker do
  @moduledoc """
  Daily sweep: emits `credits.expiring_soon` once per lot expiring within the
  window (default 7 days). Idempotent via `credit_lots.expiring_soon_notified_at`.
  Owned by WP-12.

  Args: `tenant_id` (required), optional `now` (ISO-8601) and `days`.
  """

  use SportsCoachBookings.Core.TenantWorker, queue: :default

  alias SportsCoachBookings.Credits

  @impl SportsCoachBookings.Core.TenantWorker
  def perform_with_tenant(%Oban.Job{args: args}) do
    now = parse_now(args["now"]) || DateTime.utc_now()
    days = args["days"] || 7

    case Credits.notify_expiring_soon(now, days) do
      {:ok, _lots} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp parse_now(nil), do: nil

  defp parse_now(iso8601) do
    case DateTime.from_iso8601(iso8601) do
      {:ok, datetime, _offset} -> datetime
      _ -> nil
    end
  end
end
