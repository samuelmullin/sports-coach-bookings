defmodule SportsCoachBookings.Customers.Household do
  @moduledoc """
  A household groups the players a family manages. Tenant-owned (RLS).

  One household per customer user in MVP. All members are managers with equal
  access to the household's players, bookings, and purchases.
  """

  use SportsCoachBookings.Core.TenantSchema

  alias SportsCoachBookings.Customers.HouseholdMember

  @type t :: %__MODULE__{}

  schema "households" do
    field :tenant_id, :binary_id
    field :name, :string

    has_many :members, HouseholdMember, foreign_key: :household_id

    timestamps()
  end

  @doc false
  def changeset(household, attrs) do
    household
    |> Ecto.Changeset.cast(attrs, [:tenant_id, :name])
    |> Ecto.Changeset.validate_required([:tenant_id])
    |> Ecto.Changeset.validate_length(:name, max: 120)
  end
end
