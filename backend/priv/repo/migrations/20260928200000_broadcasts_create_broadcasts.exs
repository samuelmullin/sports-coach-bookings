defmodule SportsCoachBookings.Repo.Migrations.BroadcastsCreateBroadcasts do
  use Ecto.Migration

  import SportsCoachBookings.Core.Migration

  def change do
    # One row per staff-authored broadcast. Tenant-owned (RLS enabled and forced).
    # `segment` holds the embedded, AND-composable segment definition, `stats` a
    # snapshot of the delivery counts at send time (history is computed live).
    tenant_table :broadcasts do
      add :subject, :string, null: false
      add :body_markdown, :text, null: false
      # Ecto enum: operational | marketing.
      add :category, :string, null: false, default: "marketing"
      add :segment, :map, null: false, default: %{}
      # Ecto enum: draft | scheduled | sending | sent | cancelled.
      add :status, :string, null: false, default: "draft"
      add :scheduled_for, :utc_datetime_usec
      add :sent_at, :utc_datetime_usec
      # Cross-context (Staff), plain uuid, no FK.
      add :created_by, :binary_id
      add :recipient_count, :integer, null: false, default: 0
      add :stats, :map, null: false, default: %{}
    end

    create index(:broadcasts, [:tenant_id, :status])
    create index(:broadcasts, [:tenant_id, :inserted_at])

    create constraint(:broadcasts, :broadcasts_category_check,
             check: "category IN ('operational', 'marketing')"
           )

    create constraint(:broadcasts, :broadcasts_status_check,
             check: "status IN ('draft', 'scheduled', 'sending', 'sent', 'cancelled')"
           )

    create constraint(:broadcasts, :broadcasts_recipient_count_non_negative,
             check: "recipient_count >= 0"
           )
  end
end
