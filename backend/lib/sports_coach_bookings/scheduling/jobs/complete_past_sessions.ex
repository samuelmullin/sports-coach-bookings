defmodule SportsCoachBookings.Scheduling.Jobs.CompletePastSessions do
  @moduledoc """
  Nightly job: marks past, still-`scheduled` sessions in the tenant as
  `completed`. Idempotent — a second run matches nothing.
  """

  use SportsCoachBookings.Core.TenantWorker, queue: :default, max_attempts: 3

  alias SportsCoachBookings.Scheduling

  @impl SportsCoachBookings.Core.TenantWorker
  def perform_with_tenant(%Oban.Job{}) do
    {:ok, _count} = Scheduling.mark_completed()
    :ok
  end
end
