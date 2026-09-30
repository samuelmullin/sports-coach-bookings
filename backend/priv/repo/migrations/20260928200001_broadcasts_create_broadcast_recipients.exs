defmodule SportsCoachBookings.Repo.Migrations.BroadcastsCreateBroadcastRecipients do
  use Ecto.Migration

  import SportsCoachBookings.Core.Migration

  def change do
    # One row per (broadcast, recipient). The unique index on
    # `(tenant_id, broadcast_id, email)` is what makes a re-run of a send
    # idempotent: resolving the segment again never inserts a second row, and the
    # engine's per-recipient idempotency key never sends a second email.
    tenant_table :broadcast_recipients do
      add :broadcast_id, references(:broadcasts, type: :uuid, on_delete: :delete_all), null: false

      # Ecto enum: customer_user | staff_user | email.
      add :recipient_type, :string, null: false, default: "customer_user"
      add :recipient_id, :binary_id
      add :email, :string, null: false
      # Cross-context (Customers), plain uuid, no FK.
      add :household_id, :binary_id
      # Ecto enum: pending | sent | suppressed | failed.
      add :status, :string, null: false, default: "pending"
      add :batch_index, :integer, null: false, default: 0
      # Cross-context (Notifications delivery tracking), plain uuids, no FK.
      add :message_id, :binary_id
      add :delivery_id, :binary_id
      add :sent_at, :utc_datetime_usec
      add :error, :string
    end

    create unique_index(:broadcast_recipients, [:tenant_id, :broadcast_id, :email])
    create index(:broadcast_recipients, [:tenant_id, :broadcast_id, :status])
    create index(:broadcast_recipients, [:tenant_id, :broadcast_id, :batch_index])

    create constraint(:broadcast_recipients, :broadcast_recipients_status_check,
             check: "status IN ('pending', 'sent', 'suppressed', 'failed')"
           )
  end
end
