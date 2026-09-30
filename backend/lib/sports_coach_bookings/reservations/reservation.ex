defmodule SportsCoachBookings.Reservations.Reservation do
  @moduledoc """
  A guest reservation: a short-lived hold on one or more session seats, created
  anonymously before sign-up and converted to real bookings after auth. Owned by
  the Reservations context.

  The bearer token is returned to the caller once and only its SHA-256
  (`token_hash`) is stored. Seat counters on the referenced sessions are moved
  exclusively through `SportsCoachBookings.Scheduling.Seats`; this schema never
  writes them.
  """

  use SportsCoachBookings.Core.TenantSchema

  @type t :: %__MODULE__{}

  @statuses [:active, :converted, :expired, :released]

  schema "reservations" do
    field :tenant_id, :binary_id
    field :token_hash, :binary
    # Cross-context (Catalog), plain uuid.
    field :offering_id, :binary_id

    field :status, Ecto.Enum, values: @statuses, default: :active
    field :expires_at, :utc_datetime_usec
    field :last_activity_at, :utc_datetime_usec

    # Cross-context (Customers), set on convert.
    field :household_id, :binary_id
    field :converted_at, :utc_datetime_usec

    has_many :reservation_sessions, SportsCoachBookings.Reservations.ReservationSession

    # Populated by `Reservations.serialize/1` (not persisted): the
    # `%{session_id, starts_at, ends_at}` summaries for the API.
    field :session_summaries, :any, virtual: true, default: []

    timestamps()
  end

  @doc "Reservation statuses."
  @spec statuses() :: [atom()]
  def statuses, do: @statuses

  @doc false
  def create_changeset(reservation, attrs) do
    reservation
    |> Ecto.Changeset.cast(attrs, [
      :tenant_id,
      :token_hash,
      :offering_id,
      :status,
      :expires_at,
      :last_activity_at
    ])
    |> Ecto.Changeset.validate_required([
      :tenant_id,
      :token_hash,
      :status,
      :expires_at,
      :last_activity_at
    ])
    |> Ecto.Changeset.unique_constraint([:tenant_id, :token_hash])
  end

  @doc false
  def update_changeset(reservation, attrs) do
    reservation
    |> Ecto.Changeset.cast(attrs, [
      :status,
      :expires_at,
      :last_activity_at,
      :household_id,
      :converted_at
    ])
  end
end
