defmodule SportsCoachBookings.Customers.Policy do
  @moduledoc """
  Authorization for customer accounts and households. Owned by WP-02.

  | Actor | Customer admin | Household |
  |---|---|---|
  | Owner / admin | Search, view, edit contact, reset password, deactivate/reactivate | View + list |
  | Coach | None | None |
  | Household manager | Own self-service account only | Read + invite/leave their own household |
  | Other customers | None | None |
  | Anonymous | None | None |

  The rule that only a `primary` member may remove other managers or transfer the
  primary role is enforced in `SportsCoachBookings.Customers` (the actor does not
  carry the member role); the policy grants these actions only within the actor's
  own household.
  """

  use SportsCoachBookings.Core.Policy

  alias SportsCoachBookings.Core.CustomerActor
  alias SportsCoachBookings.Core.StaffActor
  alias SportsCoachBookings.Customers.CustomerUser
  alias SportsCoachBookings.Customers.Household
  alias SportsCoachBookings.Customers.HouseholdMember

  @admin_actions [:list, :search, :get, :update, :reset_password, :deactivate, :reactivate]
  @account_actions [
    :get,
    :update,
    :update_password,
    :update_email,
    :notification_preferences
  ]
  @household_actions [
    :get,
    :list_members,
    :invite,
    :list_invites,
    :leave,
    :remove_member,
    :transfer_primary
  ]

  ## Owner / admin

  def authorize(%StaffActor{role: role}, action, :customer)
      when role in [:owner, :admin] and action in @admin_actions,
      do: :ok

  def authorize(%StaffActor{role: role} = actor, action, %CustomerUser{} = customer)
      when role in [:owner, :admin] and action in @admin_actions do
    tenant_ok?(actor, customer)
  end

  def authorize(%StaffActor{role: role}, action, :household)
      when role in [:owner, :admin] and action in [:list, :search, :get],
      do: :ok

  def authorize(%StaffActor{role: role} = actor, :get, %Household{} = household)
      when role in [:owner, :admin] do
    tenant_ok?(actor, household)
  end

  def authorize(%StaffActor{role: role} = actor, :list_members, %Household{} = household)
      when role in [:owner, :admin] do
    tenant_ok?(actor, household)
  end

  ## Household manager

  def authorize(%CustomerActor{}, action, :account) when action in @account_actions, do: :ok

  def authorize(%CustomerActor{}, action, :household) when action in @household_actions, do: :ok

  def authorize(%CustomerActor{} = actor, action, %Household{} = household)
      when action in @household_actions do
    if owns_household?(actor, household), do: :ok, else: {:error, :forbidden}
  end

  def authorize(%CustomerActor{} = actor, action, %HouseholdMember{} = member)
      when action in [:remove_member, :transfer_primary] do
    if owns_household?(actor, member), do: :ok, else: {:error, :forbidden}
  end

  ## Default: deny.

  def authorize(_actor, _action, _resource), do: {:error, :forbidden}

  @doc "The actions the policy understands. Used by tests and tooling."
  @spec actions() :: [atom()]
  def actions, do: Enum.uniq(@admin_actions ++ @account_actions ++ @household_actions)

  defp owns_household?(
         %CustomerActor{household_id: household_id, tenant_id: tenant_id},
         %Household{id: household_id, tenant_id: tenant_id}
       ),
       do: true

  defp owns_household?(
         %CustomerActor{household_id: household_id, tenant_id: tenant_id},
         %HouseholdMember{household_id: household_id, tenant_id: tenant_id}
       ),
       do: true

  defp owns_household?(_actor, _resource), do: false

  defp tenant_ok?(%StaffActor{tenant_id: tenant_id}, %{tenant_id: tenant_id}), do: :ok
  defp tenant_ok?(%StaffActor{}, _resource), do: {:error, :forbidden}
end
