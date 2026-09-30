defmodule SportsCoachBookings.Staff.Membership do
  @moduledoc """
  Links a global `StaffUser` to a tenant with a role. Tenant-owned (RLS).

  `status: :removed` is the soft-removal state; a removed membership grants no
  access even though the row is retained for history.
  """

  use SportsCoachBookings.Core.TenantSchema

  alias SportsCoachBookings.Staff.StaffUser

  @type t :: %__MODULE__{}
  @type role :: :owner | :admin | :coach

  schema "memberships" do
    field :tenant_id, :binary_id

    belongs_to :staff_user, StaffUser

    field :role, Ecto.Enum, values: [:owner, :admin, :coach]
    field :status, Ecto.Enum, values: [:active, :removed], default: :active
    field :display_name, :string
    field :bio, :string
    field :photo_key, :string

    timestamps()
  end

  @doc false
  def changeset(membership, attrs) do
    membership
    |> Ecto.Changeset.cast(attrs, [
      :tenant_id,
      :staff_user_id,
      :role,
      :status,
      :display_name,
      :bio,
      :photo_key
    ])
    |> Ecto.Changeset.validate_required([:tenant_id, :staff_user_id, :role])
    |> Ecto.Changeset.unique_constraint([:tenant_id, :staff_user_id])
  end
end
