defmodule SportsCoachBookings.Repo.Migrations.SchedulingCreateSessionSeries do
  use Ecto.Migration

  import SportsCoachBookings.Core.Migration

  def change do
    tenant_table :session_series do
      # ISO weekday numbers (1 = Monday .. 7 = Sunday).
      add :weekdays, {:array, :integer}, null: false, default: []
      # Local wall-clock start time; combined with each occurrence's local date
      # and `timezone` so DST transitions keep the wall-clock time.
      add :start_time_local, :time, null: false
      add :duration_minutes, :integer, null: false
      add :starts_on, :date, null: false
      add :ends_on, :date
      add :timezone, :string, null: false
      # Cross-context (Catalog): plain uuid, no FK.
      add :offering_id, :binary_id, null: false
      add :venue_id, :binary_id, null: false
    end

    create constraint(:session_series, :weekdays_not_empty,
             check: "array_length(weekdays, 1) >= 1"
           )

    create constraint(:session_series, :weekdays_valid,
             check: "weekdays <@ ARRAY[1,2,3,4,5,6,7]::integer[]"
           )

    create constraint(:session_series, :duration_positive, check: "duration_minutes > 0")

    create constraint(:session_series, :date_range_ordered,
             check: "ends_on IS NULL OR ends_on >= starts_on"
           )

    create index(:session_series, [:tenant_id, :offering_id])
    create index(:session_series, [:tenant_id, :venue_id])
  end
end
