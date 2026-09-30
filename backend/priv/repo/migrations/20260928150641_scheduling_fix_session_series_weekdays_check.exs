defmodule SportsCoachBookings.Repo.Migrations.SchedulingFixSessionSeriesWeekdaysCheck do
  use Ecto.Migration

  def up do
    # `array_length('{}', 1)` is NULL, and a NULL CHECK passes, so the original
    # constraint never rejected an empty weekday set. `cardinality/1` returns 0.
    drop constraint(:session_series, :weekdays_not_empty)

    create constraint(:session_series, :weekdays_not_empty, check: "cardinality(weekdays) >= 1")
  end

  def down do
    drop constraint(:session_series, :weekdays_not_empty)

    create constraint(:session_series, :weekdays_not_empty,
             check: "array_length(weekdays, 1) >= 1"
           )
  end
end
