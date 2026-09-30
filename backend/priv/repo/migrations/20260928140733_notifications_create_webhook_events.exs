defmodule SportsCoachBookings.Repo.Migrations.NotificationsCreateWebhookEvents do
  use Ecto.Migration

  def change do
    # Platform table (no `tenant_id`, no RLS): provider webhooks are delivered
    # without tenant context and the tenant is resolved from the payload. The
    # unique `(provider, event_id)` index makes webhook replays a no-op.
    create table(:notifications_webhook_events, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :provider, :string, null: false
      add :event_id, :string, null: false
      add :type, :string, null: false
      add :payload, :map
      add :processed_at, :utc_datetime_usec
      add :error, :text

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:notifications_webhook_events, [:provider, :event_id])
  end
end
