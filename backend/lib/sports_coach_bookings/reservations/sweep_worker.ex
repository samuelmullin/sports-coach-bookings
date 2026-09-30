defmodule SportsCoachBookings.Reservations.SweepWorker do
  @moduledoc """
  Platform-level Oban cron worker: expires guest reservation holds whose 10-minute
  window has lapsed. Runs every minute (see `config/config.exs`). Not a
  `TenantWorker` because the sweep spans all tenants; `Reservations.expire_due/1`
  fans out per tenant. Owned by the Reservations context.
  """

  use Oban.Worker, queue: :default

  alias SportsCoachBookings.Reservations

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    _count = Reservations.expire_due(DateTime.utc_now())
    :ok
  end
end
