defmodule SportsCoachBookings.Customers.HouseholdMember do
  @moduledoc """
  Links a customer user to a household with a role. Tenant-owned (RLS).

  `role: :primary` is the household owner and the only member who may remove
  other members or transfer the primary role. `role: :manager` has equal access
  to the household's players, bookings, and purchases.
  """

  use SportsCoachBookings.Core.TenantSchema

  alias SportsCoachBookings.Customers.CustomerUser
  alias SportsCoachBookings.Customers.Household

  @type t :: %__MODULE__{}
  @type role :: :primary | :manager

  schema "household_members" do
    field :tenant_id, :binary_id
    field :role, Ecto.Enum, values: [:primary, :manager]
    field :relationship, :string

    belongs_to :household, Household
    belongs_to :customer_user, CustomerUser

    timestamps()
  end

  @doc false
  def changeset(member, attrs) do
    member
    |> Ecto.Changeset.cast(attrs, [
      :tenant_id,
      :household_id,
      :customer_user_id,
      :role,
      :relationship
    ])
    |> Ecto.Changeset.validate_required([
      :tenant_id,
      :household_id,
      :customer_user_id,
      :role
    ])
    |> Ecto.Changeset.unique_constraint([:household_id, :customer_user_id])
    |> Ecto.Changeset.unique_constraint([:tenant_id, :customer_user_id])
  end

  @doc "True when the member is the household's primary manager."
  @spec primary?(t()) :: boolean()
  def primary?(%__MODULE__{role: :primary}), do: true
  def primary?(%__MODULE__{}), do: false
end
