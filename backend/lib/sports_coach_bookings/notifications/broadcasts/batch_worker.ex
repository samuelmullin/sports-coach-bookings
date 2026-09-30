defmodule SportsCoachBookings.Notifications.Broadcasts.BatchWorker do
  @moduledoc """
  Sends one batch (up to 100 recipients) of a broadcast.

  Each recipient is delivered through `Notifications.deliver/4` with a stable
  per-recipient idempotency key, so replaying the job never double-sends.
  """

  use SportsCoachBookings.Core.TenantWorker, queue: :notifications, max_attempts: 5

  alias SportsCoachBookings.Notifications.Broadcasts

  @impl SportsCoachBookings.Core.TenantWorker
  def perform_with_tenant(%Oban.Job{args: %{"broadcast_id" => broadcast_id, "batch" => batch}}) do
    Broadcasts.process_batch(broadcast_id, batch)
  end

  def perform_with_tenant(%Oban.Job{}), do: :ok
end
