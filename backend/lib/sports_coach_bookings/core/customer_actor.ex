defmodule SportsCoachBookings.Core.CustomerActor do
  @moduledoc """
  The actor built for an authenticated customer-portal request.

  `customer_user` is the authenticated account and `household` is their
  household in the resolved tenant. Household managers act on behalf of the
  players in their household.
  """

  @enforce_keys [:customer_user_id, :household_id, :tenant_id]
  defstruct [:customer_user_id, :household_id, :tenant_id, :customer_user, :household]

  @type t :: %__MODULE__{
          customer_user_id: binary(),
          household_id: binary(),
          tenant_id: binary(),
          customer_user: term() | nil,
          household: term() | nil
        }

  @doc "Builds an actor from explicit fields."
  @spec new(keyword()) :: t()
  def new(fields), do: struct!(__MODULE__, fields)
end
