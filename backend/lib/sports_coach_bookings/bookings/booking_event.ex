defmodule SportsCoachBookings.Bookings.BookingEvent do
  @moduledoc "Append-only booking history for staff. Owned by WP-14."

  use SportsCoachBookings.Core.TenantSchema

  @type t :: %__MODULE__{}

  schema "booking_events" do
    field :tenant_id, :binary_id
    field :kind, :string
    field :actor_type, :string
    field :actor_id, :binary_id
    field :data, :map, default: %{}

    belongs_to :booking, SportsCoachBookings.Bookings.Booking

    timestamps(updated_at: false)
  end

  @doc false
  def changeset(event, attrs) do
    event
    |> Ecto.Changeset.cast(attrs, [:tenant_id, :booking_id, :kind, :actor_type, :actor_id, :data])
    |> Ecto.Changeset.validate_required([:tenant_id, :booking_id, :kind])
  end
end
