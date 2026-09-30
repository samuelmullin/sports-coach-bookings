defmodule SportsCoachBookings.Core.StaffActor do
  @moduledoc """
  The actor built for an authenticated staff request.

  `membership` is the caller's membership in the *resolved* tenant, so `role`
  is always scoped to that tenant. `staff_user` is the global identity, which
  may have memberships in several tenants.
  """

  @enforce_keys [:staff_user_id, :tenant_id, :role]
  defstruct [:staff_user_id, :membership, :tenant_id, :role]

  @type role :: :owner | :admin | :coach
  @type t :: %__MODULE__{
          staff_user_id: binary(),
          membership: term() | nil,
          tenant_id: binary(),
          role: role()
        }

  @doc "Builds an actor from a membership or explicit fields."
  @spec new(keyword()) :: t()
  def new(fields), do: struct!(__MODULE__, fields)

  @doc "True for owners and admins."
  @spec manager?(t()) :: boolean()
  def manager?(%__MODULE__{role: role}), do: role in [:owner, :admin]

  @doc "True for coaches only."
  @spec coach?(t()) :: boolean()
  def coach?(%__MODULE__{role: :coach}), do: true
  def coach?(%__MODULE__{}), do: false
end
