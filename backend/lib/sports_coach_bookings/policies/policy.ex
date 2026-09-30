defmodule SportsCoachBookings.Policies.Policy do
  @moduledoc """
  Authorization for cancellation policies and offering assignments. Owned by
  WP-10.

  | Actor | Policies / assignments | Portal summary |
  |---|---|---|
  | Owner / admin | Full CRUD, set default, assign, simulate | — |
  | Coach | Read + simulate | — |
  | Customer / anonymous | — | Read the summary for an offering |

  A staff actor may only act on a policy in their own tenant.
  """

  use SportsCoachBookings.Core.Policy

  alias SportsCoachBookings.Core.StaffActor
  alias SportsCoachBookings.Policies.CancellationPolicy

  @staff_actions [
    :list,
    :get,
    :create,
    :update,
    :archive,
    :set_default,
    :assign,
    :unassign,
    :simulate
  ]
  @staff_resources [:cancellation_policy, :offering_policy_assignment]

  def authorize(%StaffActor{role: role}, action, resource)
      when role in [:owner, :admin] and action in @staff_actions and
             resource in @staff_resources,
      do: :ok

  def authorize(%StaffActor{role: role, tenant_id: tenant_id}, action, %CancellationPolicy{
        tenant_id: tenant_id
      })
      when role in [:owner, :admin] and action in @staff_actions,
      do: :ok

  def authorize(%StaffActor{role: :coach}, action, :cancellation_policy)
      when action in [:list, :get, :simulate],
      do: :ok

  def authorize(_actor, :summary, :offering_policy), do: :ok

  def authorize(_actor, _action, _resource), do: {:error, :forbidden}

  @doc "Every action the policy understands. Used by tests and tooling."
  @spec actions() :: [atom()]
  def actions, do: Enum.uniq(@staff_actions ++ [:summary])
end
