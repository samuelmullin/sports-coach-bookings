defmodule SportsCoachBookings.Repo.Migrations.CoreRateLimitSlidingWindow do
  use Ecto.Migration

  # Exact, shared sliding-window history. These rows are disposable operational
  # state, so the table remains UNLOGGED. Advisory locks in the backend serialize
  # a key across application machines. Keep the old counter table during the
  # rollout so an old application instance remains compatible until it drains;
  # a later migration can remove that disposable table.
  def up do
    execute """
    CREATE UNLOGGED TABLE rate_limit_events (
      id bigserial PRIMARY KEY,
      key text NOT NULL,
      hit_at timestamptz NOT NULL
    )
    """

    execute "CREATE INDEX rate_limit_events_key_hit_idx ON rate_limit_events (key, hit_at)"
    execute "CREATE INDEX rate_limit_events_hit_idx ON rate_limit_events (hit_at)"
  end

  def down do
    execute "DROP TABLE rate_limit_events"
  end
end
