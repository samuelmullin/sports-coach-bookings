defmodule SportsCoachBookings.Bookings.SessionInvitation do
  @moduledoc "A one-seat invitation and, when allowed, its temporary capacity reservation."

  use SportsCoachBookings.Core.TenantSchema

  @type t :: %__MODULE__{}
  @statuses [:pending, :accepted, :declined, :expired, :cancelled]
  @payment_modes [:split, :organizer]
  @seat_statuses [:reserved, :purchased, :released]

  schema "session_invitations" do
    field :tenant_id, :binary_id
    field :session_id, :binary_id
    field :organizer_household_id, :binary_id
    field :organizer_email, :string
    field :invitee_household_id, :binary_id
    field :invitee_player_id, :binary_id
    field :email, :string
    field :token_hash, :binary
    field :status, Ecto.Enum, values: @statuses, default: :pending
    field :payment_mode, Ecto.Enum, values: @payment_modes
    field :seat_status, Ecto.Enum, values: @seat_statuses, default: :reserved
    field :expires_at, :utc_datetime_usec
    field :accepted_at, :utc_datetime_usec
    field :declined_at, :utc_datetime_usec
    field :booking_id, :binary_id
    field :resend_count, :integer, default: 0
    field :last_sent_at, :utc_datetime_usec
    timestamps()
  end

  @doc false
  def changeset(invitation, attrs) do
    invitation
    |> Ecto.Changeset.cast(attrs, [
      :tenant_id,
      :session_id,
      :organizer_household_id,
      :organizer_email,
      :invitee_household_id,
      :invitee_player_id,
      :email,
      :token_hash,
      :status,
      :payment_mode,
      :seat_status,
      :expires_at,
      :accepted_at,
      :declined_at,
      :booking_id,
      :resend_count,
      :last_sent_at
    ])
    |> Ecto.Changeset.validate_required([
      :tenant_id,
      :session_id,
      :organizer_household_id,
      :organizer_email,
      :email,
      :token_hash,
      :payment_mode,
      :seat_status
    ])
    |> Ecto.Changeset.validate_format(:email, ~r/^[^@,;\s]+@[^@,;\s]+$/i)
    |> Ecto.Changeset.validate_number(:resend_count, greater_than_or_equal_to: 0)
    |> Ecto.Changeset.unique_constraint([:tenant_id, :token_hash])
  end

  @doc "True when a pending invitation's temporary reservation has elapsed."
  @spec expired?(t(), DateTime.t()) :: boolean()
  def expired?(%__MODULE__{status: :pending, expires_at: %DateTime{} = expires_at}, now),
    do: DateTime.compare(expires_at, now) != :gt

  def expired?(_invitation, _now), do: false
end
