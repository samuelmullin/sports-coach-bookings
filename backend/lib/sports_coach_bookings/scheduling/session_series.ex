defmodule SportsCoachBookings.Scheduling.SessionSeries do
  @moduledoc """
  A recurrence definition used only at creation/edit time.

  Sessions are always materialised rows; there is no runtime RRULE expansion.
  Because each occurrence is built from a local date + `start_time_local` +
  `timezone`, the wall-clock time is preserved across DST transitions.
  """

  use SportsCoachBookings.Core.TenantSchema

  alias SportsCoachBookings.Scheduling.Session

  @type t :: %__MODULE__{}

  schema "session_series" do
    field :tenant_id, :binary_id
    field :weekdays, {:array, :integer}, default: []
    field :start_time_local, :time
    field :duration_minutes, :integer
    field :starts_on, :date
    field :ends_on, :date
    field :timezone, :string
    # Cross-context (Catalog).
    field :offering_id, :binary_id
    field :venue_id, :binary_id

    has_many :sessions, Session, foreign_key: :series_id

    timestamps()
  end

  @doc false
  def changeset(series, attrs) do
    series
    |> Ecto.Changeset.cast(attrs, [
      :tenant_id,
      :weekdays,
      :start_time_local,
      :duration_minutes,
      :starts_on,
      :ends_on,
      :timezone,
      :offering_id,
      :venue_id
    ])
    |> Ecto.Changeset.validate_required([
      :tenant_id,
      :weekdays,
      :start_time_local,
      :duration_minutes,
      :starts_on,
      :timezone,
      :offering_id,
      :venue_id
    ])
    |> Ecto.Changeset.validate_number(:duration_minutes, greater_than: 0)
    |> validate_weekdays()
    |> validate_date_range()
  end

  defp validate_weekdays(changeset) do
    Ecto.Changeset.validate_change(changeset, :weekdays, fn :weekdays, weekdays ->
      if is_list(weekdays) and weekdays != [] and Enum.all?(weekdays, &(&1 in 1..7)) do
        []
      else
        [weekdays: "must be a non-empty list of ISO weekday numbers (1..7)"]
      end
    end)
  end

  defp validate_date_range(changeset) do
    starts_on = Ecto.Changeset.get_field(changeset, :starts_on)
    ends_on = Ecto.Changeset.get_field(changeset, :ends_on)

    if starts_on && ends_on && Date.compare(ends_on, starts_on) == :lt do
      Ecto.Changeset.add_error(changeset, :ends_on, "must be on or after starts_on")
    else
      changeset
    end
  end
end
