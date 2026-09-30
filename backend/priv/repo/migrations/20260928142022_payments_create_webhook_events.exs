defmodule SportsCoachBookings.Repo.Migrations.PaymentsCreateWebhookEvents do
  use Ecto.Migration

  def change do
    # Platform table (no `tenant_id`, no RLS): provider webhooks arrive with no
    # tenant context and the tenant is resolved from the payload/account. Named
    # `payments_webhook_events` to avoid clashing with wp-05's
    # `notifications_webhook_events`. Inserts use `skip_tenant: true`; the
    # unique `(provider, event_id)` index makes replays a no-op.
    create table(:payments_webhook_events, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :provider, :string, null: false
      add :event_id, :string, null: false
      add :type, :string, null: false
      add :payload, :map
      add :processed_at, :utc_datetime_usec
      add :error, :text

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:payments_webhook_events, [:provider, :event_id])
  end
end
