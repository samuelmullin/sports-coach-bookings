defmodule SportsCoachBookings.Bookings.PrivateSessionRequest do
  @moduledoc "A customer request for an operator-approved private session."

  use SportsCoachBookings.Core.TenantSchema

  @type t :: %__MODULE__{}
  @statuses [:pending, :approved, :declined, :cancelled]

  schema "private_session_requests" do
    field :tenant_id, :binary_id
    field :offering_id, :binary_id
    field :household_id, :binary_id
    field :player_count, :integer
    field :preferred_times, {:array, :utc_datetime_usec}, default: []
    field :notes, :string
    field :status, Ecto.Enum, values: @statuses, default: :pending
    field :reviewed_by_id, :binary_id
    field :reviewed_at, :utc_datetime_usec
    field :session_id, :binary_id
    field :decline_reason, :string
    timestamps()
  end

  @doc false
  def changeset(request, attrs) do
    request
    |> Ecto.Changeset.cast(attrs, [
      :tenant_id,
      :offering_id,
      :household_id,
      :player_count,
      :preferred_times,
      :notes,
      :status,
      :reviewed_by_id,
      :reviewed_at,
      :session_id,
      :decline_reason
    ])
    |> Ecto.Changeset.validate_required([
      :tenant_id,
      :offering_id,
      :household_id,
      :player_count,
      :status
    ])
    |> Ecto.Changeset.validate_number(:player_count, greater_than_or_equal_to: 1)
  end
end
