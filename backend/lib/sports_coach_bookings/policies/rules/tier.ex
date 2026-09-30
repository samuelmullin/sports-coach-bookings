defmodule SportsCoachBookings.Policies.Rules.Tier do
  @moduledoc """
  One cancellation tier. Tiers are evaluated in order and the first match wins.

  A tier matches when the booking is cancelled at least `min_hours_before` hours
  before the session starts. `credit_outcome` is `:return` or `:forfeit`;
  `money_refund_pct` (0..100) applies to bookings paid per session.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :min_hours_before, :integer
    field :credit_outcome, Ecto.Enum, values: [:return, :forfeit]
    field :money_refund_pct, :integer
  end

  @type t :: %__MODULE__{}

  @doc false
  def changeset(tier, attrs) do
    tier
    |> cast(attrs, [:min_hours_before, :credit_outcome, :money_refund_pct])
    |> validate_required([:min_hours_before, :credit_outcome, :money_refund_pct])
    |> validate_number(:min_hours_before, greater_than_or_equal_to: 0)
    |> validate_inclusion(:credit_outcome, [:return, :forfeit])
    |> validate_number(:money_refund_pct, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
  end
end
