defmodule SportsCoachBookings.Repo.Migrations.CoreCreateRateLimitCounters do
  use Ecto.Migration

  # Shared fixed-window counters for `SportsCoachBookings.RateLimiter`'s Postgres
  # backend, so limits hold across machines. A platform table (no tenant_id, no
  # RLS): keys already embed the tenant where relevant. UNLOGGED because the
  # counters are disposable; losing them on a crash only resets the windows.
  def up do
    execute """
    CREATE UNLOGGED TABLE rate_limit_counters (
      key text PRIMARY KEY,
      count integer NOT NULL,
      window_started_at timestamptz NOT NULL
    )
    """

    execute "CREATE INDEX rate_limit_counters_window_idx ON rate_limit_counters (window_started_at)"
  end

  def down do
    execute "DROP TABLE rate_limit_counters"
  end
end
