defmodule SportsCoachBookings.Notifications.Broadcasts.ScheduleWorker do
  @moduledoc """
  Starts a scheduled broadcast when its `scheduled_for` time arrives.

  Idempotent: if the broadcast was cancelled, already sent, or is not yet due,
  `Broadcasts.start_send/2` is a no-op.
  """

  use SportsCoachBookings.Core.TenantWorker, queue: :notifications, max_attempts: 3

  alias SportsCoachBookings.Notifications.Broadcasts

  @impl SportsCoachBookings.Core.TenantWorker
  def perform_with_tenant(%Oban.Job{args: %{"broadcast_id" => broadcast_id}}) do
    case Broadcasts.start_send(broadcast_id, require_due: true) do
      {:ok, _result} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
