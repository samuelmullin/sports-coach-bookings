defmodule SportsCoachBookings.Credits.DispatchExpiryWorker do
  @moduledoc """
  Platform-level cron worker: enqueues the per-tenant credit expiry sweeps.

  Cron jobs cannot carry a tenant, so this worker fans out one
  `ExpiryWorker` and one `ExpiringSoonWorker` per active tenant. Owned by WP-12.
  """

  use Oban.Worker, queue: :default

  import Ecto.Query

  alias SportsCoachBookings.Core.Tenant
  alias SportsCoachBookings.Credits.ExpiringSoonWorker
  alias SportsCoachBookings.Credits.ExpiryWorker
  alias SportsCoachBookings.Repo

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    tenant_ids =
      Repo.all(from t in Tenant, where: t.status == :active, select: t.id)

    Enum.each(tenant_ids, fn tenant_id ->
      %{tenant_id: tenant_id} |> ExpiryWorker.new() |> Oban.insert()
      %{tenant_id: tenant_id} |> ExpiringSoonWorker.new() |> Oban.insert()
    end)

    :ok
  end
end
