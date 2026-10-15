defmodule SportsCoachBookings.Scheduling.Session do
  @moduledoc """
  A concrete, bookable coaching session (a materialised occurrence).

  `booked_count`/`held_count` are written **only** by wp-14 through
  `SportsCoachBookings.Scheduling.Seats`, and are guarded by the
  `counts_within_capacity` database check constraint.
  """

  use SportsCoachBookings.Core.TenantSchema

  alias SportsCoachBookings.Scheduling.SessionCoach
  alias SportsCoachBookings.Scheduling.SessionSeries

  @type t :: %__MODULE__{}

  @statuses [:scheduled, :cancelled, :completed]
  @visibilities [:public, :hidden]
  @access_modes [:public, :private]

  schema "sessions" do
    field :tenant_id, :binary_id
    # Cross-context (Catalog).
    field :offering_id, :binary_id
    field :venue_id, :binary_id

    field :starts_at, :utc_datetime_usec
    field :ends_at, :utc_datetime_usec

    field :capacity, :integer
    field :booked_count, :integer, default: 0
    field :held_count, :integer, default: 0

    field :status, Ecto.Enum, values: @statuses, default: :scheduled
    field :visibility, Ecto.Enum, values: @visibilities, default: :public
    field :title_override, :string
    field :notes_public, :string
    field :notes_staff, :string
    field :cancel_reason, :string
    field :show_coaches, :boolean, default: true
    field :access_mode, Ecto.Enum, values: @access_modes, default: :public
    field :party_size, :integer
    field :exclusive_household_id, :binary_id

    belongs_to :series, SessionSeries, type: :binary_id
    has_many :session_coaches, SessionCoach

    timestamps()
  end

  @doc "Statuses a session can hold."
  @spec statuses() :: [atom()]
  def statuses, do: @statuses

  @doc "Visibilities a session can hold."
  @spec visibilities() :: [atom()]
  def visibilities, do: @visibilities

  @doc "Booking access modes."
  @spec access_modes() :: [atom()]
  def access_modes, do: @access_modes

  @doc "Number of seats currently taken (confirmed + held)."
  @spec occupancy(t()) :: non_neg_integer()
  def occupancy(%__MODULE__{booked_count: booked, held_count: held}), do: booked + held

  @doc "Seats still available."
  @spec seats_left(t()) :: integer()
  def seats_left(%__MODULE__{capacity: capacity} = session), do: capacity - occupancy(session)

  @doc false
  def create_changeset(session, attrs) do
    session
    |> Ecto.Changeset.cast(attrs, [
      :tenant_id,
      :offering_id,
      :venue_id,
      :starts_at,
      :ends_at,
      :capacity,
      :visibility,
      :title_override,
      :notes_public,
      :notes_staff,
      :show_coaches,
      :access_mode,
      :party_size,
      :exclusive_household_id,
      :series_id
    ])
    |> Ecto.Changeset.validate_required([
      :tenant_id,
      :offering_id,
      :venue_id,
      :starts_at,
      :ends_at,
      :capacity
    ])
    |> Ecto.Changeset.validate_number(:capacity, greater_than_or_equal_to: 1)
    |> Ecto.Changeset.validate_number(:party_size, greater_than_or_equal_to: 1)
    |> validate_time_span()
  end

  @doc false
  def update_changeset(session, attrs) do
    session
    |> Ecto.Changeset.cast(attrs, [
      :starts_at,
      :ends_at,
      :venue_id,
      :capacity,
      :visibility,
      :title_override,
      :notes_public,
      :notes_staff,
      :show_coaches,
      :access_mode,
      :party_size,
      :exclusive_household_id
    ])
    |> Ecto.Changeset.validate_number(:capacity, greater_than_or_equal_to: 1)
    |> Ecto.Changeset.validate_number(:party_size, greater_than_or_equal_to: 1)
    |> validate_time_span()
    |> validate_capacity_vs_bookings()
  end

  @doc false
  def cancel_changeset(session, attrs) do
    session
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.cast(attrs, [:cancel_reason])
    |> Ecto.Changeset.put_change(:status, :cancelled)
  end

  @doc false
  def complete_changeset(session) do
    Ecto.Changeset.change(session, status: :completed)
  end

  defp validate_time_span(changeset) do
    starts_at = Ecto.Changeset.get_field(changeset, :starts_at)
    ends_at = Ecto.Changeset.get_field(changeset, :ends_at)

    if starts_at && ends_at && DateTime.compare(ends_at, starts_at) != :gt do
      Ecto.Changeset.add_error(changeset, :ends_at, "must be after starts_at")
    else
      changeset
    end
  end

  defp validate_capacity_vs_bookings(changeset) do
    capacity = Ecto.Changeset.get_field(changeset, :capacity)
    session = changeset.data

    if capacity && capacity < occupancy(session) do
      Ecto.Changeset.add_error(changeset, :capacity, "is below the confirmed + held bookings")
    else
      changeset
    end
  end
end
