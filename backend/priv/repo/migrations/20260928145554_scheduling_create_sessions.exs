defmodule SportsCoachBookings.Repo.Migrations.SchedulingCreateSessions do
  use Ecto.Migration

  import SportsCoachBookings.Core.Migration

  def change do
    tenant_table :sessions do
      # Cross-context (Catalog): plain uuid, no FK.
      add :offering_id, :binary_id, null: false
      add :venue_id, :binary_id, null: false

      add :starts_at, :utc_datetime_usec, null: false
      add :ends_at, :utc_datetime_usec, null: false

      add :capacity, :integer, null: false
      # Written only by WP-14 through `SportsCoachBookings.Scheduling.Seats`.
      add :booked_count, :integer, null: false, default: 0
      add :held_count, :integer, null: false, default: 0

      add :status, :string, null: false, default: "scheduled"
      add :visibility, :string, null: false, default: "public"
      add :title_override, :string
      add :notes_public, :text
      add :notes_staff, :text

      add :series_id,
          references(:session_series, type: :uuid, on_delete: :nilify_all)

      add :cancel_reason, :text
    end

    create index(:sessions, [:tenant_id, :starts_at])
    create index(:sessions, [:tenant_id, :offering_id])
    create index(:sessions, [:tenant_id, :venue_id])
    create index(:sessions, [:tenant_id, :status])
    create index(:sessions, [:tenant_id, :series_id])

    create constraint(:sessions, :ends_after_starts, check: "ends_at > starts_at")
    create constraint(:sessions, :capacity_positive, check: "capacity >= 1")

    create constraint(:sessions, :counts_within_capacity,
             check: "booked_count + held_count <= capacity"
           )

    create constraint(:sessions, :counts_non_negative,
             check: "booked_count >= 0 AND held_count >= 0"
           )
  end
end
