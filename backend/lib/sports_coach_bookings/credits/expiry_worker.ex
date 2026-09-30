defmodule SportsCoachBookings.Credits.ExpiryWorker do
  @moduledoc """
  Daily sweep: expires every lapsed credit lot, appending an `expire` ledger
  entry and publishing `credits.expired`. Idempotent. Owned by WP-12.

  Args: `tenant_id` (required, injected by `TenantWorker`), optional `now`
  (ISO-8601, used by tests).
  """

  use SportsCoachBookings.Core.TenantWorker, queue: :default

  alias SportsCoachBookings.Credits

  @impl SportsCoachBookings.Core.TenantWorker
  def perform_with_tenant(%Oban.Job{args: args}) do
    now = parse_now(args["now"]) || DateTime.utc_now()

    case Credits.expire_due_lots(now) do
      {:ok, _entries} -> :ok
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
