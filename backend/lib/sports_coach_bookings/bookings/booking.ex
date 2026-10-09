defmodule SportsCoachBookings.Bookings.Booking do
  @moduledoc """
  A seat in a session for a player. Owned by WP-14 (Bookings).

  The row is the durable record of the booking: the payment method, the policy
  snapshot taken at booking time (never recomputed), and the outcome applied if
  it was cancelled. Only WP-14 writes `bookings`; `Scheduling.Seats` owns the
  session counters.
  """

  use SportsCoachBookings.Core.TenantSchema

  @type t :: %__MODULE__{}

  @statuses [:held, :confirmed, :cancelled, :attended, :no_show]
  @payment_methods [:credits, :paid, :comp]

  schema "bookings" do
    field :tenant_id, :binary_id

    # Cross-context references (plain uuids, no FK): scheduling, players,
    # customers.
    field :session_id, :binary_id
    field :player_id, :binary_id
    field :household_id, :binary_id
    field :beneficiary_household_id, :binary_id
    field :session_invitation_id, :binary_id

    field :booked_by_type, :string
    field :booked_by_id, :binary_id

    field :status, Ecto.Enum, values: @statuses, default: :held
    field :payment_method, Ecto.Enum, values: @payment_methods

    field :credits_used, :integer, default: 0
    field :order_line_id, :binary_id

    field :policy_snapshot, :map, default: %{}
    field :rebook_count, :integer, default: 0

    belongs_to :rebooked_from, __MODULE__, type: :binary_id
    belongs_to :rebooked_to, __MODULE__, type: :binary_id

    field :hold_expires_at, :utc_datetime_usec
    field :cancelled_at, :utc_datetime_usec
    field :free_change_until, :utc_datetime_usec
    field :cancel_outcome, :map

    field :paid_amount, :integer, default: 0
    field :currency, :string

    has_many :events, SportsCoachBookings.Bookings.BookingEvent, foreign_key: :booking_id

    timestamps()
  end

  @doc "Booking statuses."
  @spec statuses() :: [atom()]
  def statuses, do: @statuses

  @doc "Payment methods."
  @spec payment_methods() :: [atom()]
  def payment_methods, do: @payment_methods

  @doc "True for a booking that still occupies a seat."
  @spec active?(t()) :: boolean()
  def active?(%__MODULE__{status: status}), do: status in [:held, :confirmed, :attended]

  @doc "True for a booking that occupies a confirmed seat (booked_count)."
  @spec confirmed?(t()) :: boolean()
  def confirmed?(%__MODULE__{status: status}), do: status in [:confirmed, :attended, :no_show]

  @doc false
  def create_changeset(booking, attrs) do
    booking
    |> Ecto.Changeset.cast(attrs, [
      :tenant_id,
      :session_id,
      :player_id,
      :household_id,
      :beneficiary_household_id,
      :session_invitation_id,
      :booked_by_type,
      :booked_by_id,
      :status,
      :payment_method,
      :credits_used,
      :order_line_id,
      :policy_snapshot,
      :rebook_count,
      :rebooked_from_id,
      :rebooked_to_id,
      :hold_expires_at,
      :free_change_until,
      :paid_amount,
      :currency
    ])
    |> Ecto.Changeset.validate_required([
      :tenant_id,
      :session_id,
      :household_id,
      :payment_method
    ])
    |> validate_player_or_invitation()
    |> Ecto.Changeset.unique_constraint(
      [:tenant_id, :session_id, :player_id],
      name: :bookings_one_active_per_session_player,
      message: "already has an active booking"
    )
  end

  @doc false
  def update_changeset(booking, attrs) do
    booking
    |> Ecto.Changeset.cast(attrs, [
      :status,
      :order_line_id,
      :credits_used,
      :rebook_count,
      :rebooked_from_id,
      :rebooked_to_id,
      :hold_expires_at,
      :cancelled_at,
      :free_change_until,
      :cancel_outcome,
      :paid_amount,
      :player_id,
      :beneficiary_household_id
    ])
  end

  defp validate_player_or_invitation(changeset) do
    if Ecto.Changeset.get_field(changeset, :player_id) ||
         Ecto.Changeset.get_field(changeset, :session_invitation_id) do
      changeset
    else
      Ecto.Changeset.add_error(changeset, :player_id, "or an invitation is required")
    end
  end
end
