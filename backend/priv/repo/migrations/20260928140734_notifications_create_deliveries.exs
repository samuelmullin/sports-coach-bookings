defmodule SportsCoachBookings.Repo.Migrations.NotificationsCreateDeliveries do
  use Ecto.Migration

  import SportsCoachBookings.Core.Migration

  def change do
    # One row per recipient of a message. Tenant-owned (RLS enabled and forced).
    tenant_table :deliveries do
      add :message_id, references(:messages, type: :uuid, on_delete: :delete_all), null: false
      add :recipient_type, :string, null: false
      add :recipient_id, :uuid
      add :email, :citext, null: false
      add :status, :string, null: false, default: "queued"
      add :provider_ref, :string
      add :sent_at, :utc_datetime_usec
      add :delivered_at, :utc_datetime_usec
      add :bounced_at, :utc_datetime_usec
      add :error, :text
    end

    create index(:deliveries, [:message_id])
    create index(:deliveries, [:tenant_id, :email, :inserted_at])
    create index(:deliveries, [:tenant_id, :provider_ref])
  end
end
