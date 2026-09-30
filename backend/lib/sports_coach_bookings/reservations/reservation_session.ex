defmodule SportsCoachBookings.Reservations.ReservationSession do
  @moduledoc """
  Join row linking a guest reservation to one held session seat. Owned by the
  Reservations context.
  """

  use SportsCoachBookings.Core.TenantSchema

  @type t :: %__MODULE__{}

  schema "reservation_sessions" do
    field :tenant_id, :binary_id

    belongs_to :reservation, SportsCoachBookings.Reservations.Reservation, type: :binary_id

    # Cross-context (Scheduling), plain uuid.
    field :session_id, :binary_id

    timestamps()
  end

  @doc false
  def changeset(reservation_session, attrs) do
    reservation_session
    |> Ecto.Changeset.cast(attrs, [:tenant_id, :reservation_id, :session_id])
    |> Ecto.Changeset.validate_required([:tenant_id, :reservation_id, :session_id])
    |> Ecto.Changeset.unique_constraint([:reservation_id, :session_id])
  end
end
