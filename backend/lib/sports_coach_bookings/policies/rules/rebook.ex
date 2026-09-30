defmodule SportsCoachBookings.Policies.Rules.Rebook do
  @moduledoc """
  Rebooking terms: whether a booking may be rebooked, how late, and how often.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :allowed, :boolean, default: true
    field :min_hours_before, :integer
    field :max_rebooks_per_booking, :integer
    field :same_offering_only, :boolean, default: true
  end

  @type t :: %__MODULE__{}

  @doc false
  def changeset(rebook, attrs) do
    rebook
    |> cast(attrs, [:allowed, :min_hours_before, :max_rebooks_per_booking, :same_offering_only])
    |> validate_required([:allowed, :min_hours_before, :same_offering_only])
    |> validate_number(:min_hours_before, greater_than_or_equal_to: 0)
    |> validate_number(:max_rebooks_per_booking, greater_than_or_equal_to: 0)
  end
end
